`default_nettype none
//
// cam_dp -- Camellia-128 compact core datapath
//
// Implements: state register st[0:15] (byte n, n=0 is MSB byte of the 128-bit
// block), key RAM kram[0:63] (LUTRAM), funnel shifter, byte ALU, s1 S-box +
// output rotation, lane write, carry FF.  All control (phase/cnt/step/dir and
// the per-phase signal decode) lives in cam_ctrl; this module is purely
// "state register lane ^= bus" plumbing per spec section 6.
//
// Debug/trace signal names intentionally match the reference model
// (model/camellia_ref.py) and the spec: x, k, alu, bus, st.
//
module cam_dp (
    input  wire        clk,
    input  wire        rst,        // synchronous reset for the carry FF only
                                    // (st[] and kram[] are never reset -- spec 8.1/8.2)

    // control (from cam_ctrl), all combinational, gated internally by adv
    input  wire        adv,
    input  wire        xsrc_din,   // 1: x = in_data, 0: x = st[rsel]
    input  wire [3:0]  rsel,       // state register read select (byte number)
    input  wire [3:0]  kj,         // subkey byte index (0..15)
    input  wire [8:0]  ent,        // key ROM entry: {base[5:0], sh[2:0]}
    input  wire [2:0]  mode,       // ALU mode (see localparams below)
    input  wire        use_sb,     // 1: route alu through s1 + output rotation
    input  wire [2:0]  pos,        // byte position (0=MSB), used for output rotation
    input  wire [15:0] lane_en,    // state register lane write enable (bit[15-n] <-> byte n)
    input  wire        ovw,        // 1: overwrite lane with bus, 0: XOR-accumulate
    input  wire        ram_we,     // key RAM write enable
    input  wire [5:0]  ram_wa,     // key RAM write address

    input  wire [7:0]  in_data,

    output wire [7:0]  alu         // ALU output (= out_data during OUT phase)
);

    localparam MODE_XOR   = 3'd0;
    localparam MODE_XORR  = 3'd1;
    localparam MODE_ANDC  = 3'd2;
    localparam MODE_OR    = 3'd3;
    localparam MODE_PASSX = 3'd4;
    localparam MODE_PASSK = 3'd5;

    integer ni;
    integer ii;

    // ------------------------------------------------------------------
    // State register: st[n] = byte number n (n=0 is the MSB byte, i.e.
    // bits [127:120] of the 128-bit state). No reset (spec 8.1/8.2).
    // ------------------------------------------------------------------
    reg [7:0] st [0:15];

    wire [7:0] rd_byte = st[rsel];
    wire [7:0] x = xsrc_din ? in_data : rd_byte;

    // ------------------------------------------------------------------
    // Key RAM: kram[0:63], 0..15=KL, 16..31=KA, 32..63=Sigma1..4.
    // No reset (spec 8.1/8.2, needed for LUTRAM inference).
    // ------------------------------------------------------------------
    reg [7:0] kram [0:63];

    initial begin
        for (ii = 0; ii < 32; ii = ii + 1) kram[ii] = 8'h00;
        // Sigma1 = A09E667F3BCC908B
        kram[32] = 8'hA0; kram[33] = 8'h9E; kram[34] = 8'h66; kram[35] = 8'h7F;
        kram[36] = 8'h3B; kram[37] = 8'hCC; kram[38] = 8'h90; kram[39] = 8'h8B;
        // Sigma2 = B67AE8584CAA73B2
        kram[40] = 8'hB6; kram[41] = 8'h7A; kram[42] = 8'hE8; kram[43] = 8'h58;
        kram[44] = 8'h4C; kram[45] = 8'hAA; kram[46] = 8'h73; kram[47] = 8'hB2;
        // Sigma3 = C6EF372FE94F82BE
        kram[48] = 8'hC6; kram[49] = 8'hEF; kram[50] = 8'h37; kram[51] = 8'h2F;
        kram[52] = 8'hE9; kram[53] = 8'h4F; kram[54] = 8'h82; kram[55] = 8'hBE;
        // Sigma4 = 54FF53A5F1D36F1C
        kram[56] = 8'h54; kram[57] = 8'hFF; kram[58] = 8'h53; kram[59] = 8'hA5;
        kram[60] = 8'hF1; kram[61] = 8'hD3; kram[62] = 8'h6F; kram[63] = 8'h1C;
    end

    wire [5:0] base = ent[8:3];
    wire [2:0] sh   = ent[2:0];
    wire [3:0] lo0  = base[3:0] + kj;
    wire [3:0] lo1  = base[3:0] + kj + 4'd1;
    wire [5:0] a0   = {base[5:4], lo0};
    wire [5:0] a1   = {base[5:4], lo1};
    wire [5:0] a_port = ram_we ? ram_wa : a0;

    wire [7:0] m0 = kram[a_port];
    wire [7:0] m1 = kram[a1];

    // Funnel shifter: take 8 bits starting at bit `sh` of {m0,m1}.
    // (sh==0 collapses to m0 automatically since m1 shifted out of range is 0.)
    /* verilator lint_off UNUSEDSIGNAL */
    wire [15:0] funnel = {m0, m1} << sh;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [7:0]  k = funnel[15:8];

    always @(posedge clk) begin
        if (adv && ram_we) kram[ram_wa] <= x;
    end

    // ------------------------------------------------------------------
    // Carry FF (FL operation-A rotate carry). Updated only in ANDC mode.
    // ------------------------------------------------------------------
    reg carry;
    wire carry_en = (mode == MODE_ANDC);
    wire [7:0] xork = x ^ k;
    wire [7:0] xandk = x & k;

    always @(posedge clk) begin
        if (rst) carry <= 1'b0;
        else if (adv && carry_en) carry <= xandk[7];
    end

    // ------------------------------------------------------------------
    // Byte ALU
    // ------------------------------------------------------------------
    reg [7:0] alu_r;
    always @* begin
        case (mode)
            MODE_XOR:   alu_r = xork;
            MODE_XORR:  alu_r = {xork[6:0], xork[7]};   // rotl8(x^k,1)
            MODE_ANDC:  alu_r = {xandk[6:0], carry};
            MODE_OR:    alu_r = x | k;
            MODE_PASSX: alu_r = x;
            MODE_PASSK: alu_r = k;
            default:    alu_r = 8'h00;
        endcase
    end
    assign alu = alu_r;

    // ------------------------------------------------------------------
    // s1 S-box + output rotation (realises s2/s3 around the single s1 table)
    // ------------------------------------------------------------------
    wire [7:0] sbox_out;
    cam_s1 u_s1 (.a(alu_r), .d(sbox_out));

    wire [7:0] bus =
        !use_sb                      ? alu_r :
        (pos == 3'd1 || pos == 3'd4) ? {sbox_out[6:0], sbox_out[7]} :  // rotl1
        (pos == 3'd2 || pos == 3'd5) ? {sbox_out[0], sbox_out[7:1]} :  // rotr1
                                        sbox_out;

    // ------------------------------------------------------------------
    // State register write
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (adv) begin
            for (ni = 0; ni < 16; ni = ni + 1) begin
                if (lane_en[15-ni])
                    st[ni] <= ovw ? bus : (st[ni] ^ bus);
            end
        end
    end

endmodule
