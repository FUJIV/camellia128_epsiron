`default_nettype none
//
// camellia128_epsiron -- Camellia-128 compact byte-serial core (top)
//
// See docs/usage.md for the interface/usage guide.
//
module camellia128_epsiron (
    input  wire       clk,
    input  wire       rst,

    input  wire        cmd_valid,
    output wire        cmd_ready,
    input  wire [1:0]  cmd_op,     // 0:KEY 1:ENC 2:DEC 3:reserved

    input  wire        in_valid,
    output wire        in_ready,
    input  wire [7:0]  in_data,

    output wire        out_valid,
    input  wire        out_ready,
    output wire [7:0]  out_data,

    output wire        busy,
    output wire        key_valid
);

    wire        adv;
    wire        xsrc_din;
    wire [3:0]  rsel;
    wire [3:0]  kj;
    wire [8:0]  ent;
    wire [2:0]  mode;
    wire        use_sb;
    wire [2:0]  pos;
    wire [15:0] lane_en;
    wire        ovw;
    wire        ram_we;
    wire [5:0]  ram_wa;
    wire [7:0]  alu;

    cam_ctrl u_ctrl (
        .clk       (clk),
        .rst       (rst),
        .cmd_valid (cmd_valid),
        .cmd_ready (cmd_ready),
        .cmd_op    (cmd_op),
        .in_valid  (in_valid),
        .in_ready  (in_ready),
        .out_valid (out_valid),
        .out_ready (out_ready),
        .busy      (busy),
        .key_valid (key_valid),
        .adv       (adv),
        .xsrc_din  (xsrc_din),
        .rsel      (rsel),
        .kj        (kj),
        .ent       (ent),
        .mode      (mode),
        .use_sb    (use_sb),
        .pos       (pos),
        .lane_en   (lane_en),
        .ovw       (ovw),
        .ram_we    (ram_we),
        .ram_wa    (ram_wa)
    );

    cam_dp u_dp (
        .clk      (clk),
        .rst      (rst),
        .adv      (adv),
        .xsrc_din (xsrc_din),
        .rsel     (rsel),
        .kj       (kj),
        .ent      (ent),
        .mode     (mode),
        .use_sb   (use_sb),
        .pos      (pos),
        .lane_en  (lane_en),
        .ovw      (ovw),
        .ram_we   (ram_we),
        .ram_wa   (ram_wa),
        .in_data  (in_data),
        .alu      (alu)
    );

    assign out_data = alu;

endmodule
