`default_nettype none
//
// tb_trace -- T9: per-cycle trace dump for diff against model/camellia_ref.py
//
// Runs exactly one KEY command followed by one ENC or DEC command (no
// stalls), dumping every adv=1 cycle in the same format as
// `python3 model/camellia_ref.py trace KEY PT [enc|dec]`.
//
// Usage (run from the project root):
//   xvlog src/cam_s1.v src/cam_dp.v src/cam_ctrl.v src/camellia128_epsiron.v sim/tb_trace.v
//   xelab -s tb_trace_snap work.tb_trace
//   xsim tb_trace_snap -runall \
//       -testplusarg "KEY=0123456789abcdeffedcba9876543210" \
//       -testplusarg "PT=0123456789abcdeffedcba9876543210" \
//       -testplusarg "MODE=enc"
//
// Defaults to the RFC 3713 vector / enc if the plusargs are not given.
//
module tb_trace;

    localparam [1:0] OP_KEY = 2'd0, OP_ENC = 2'd1, OP_DEC = 2'd2;
    localparam CLK_PERIOD = 10;

    reg clk;
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg        rst;
    reg        cmd_valid;
    reg  [1:0] cmd_op;
    reg        in_valid;
    reg  [7:0] in_data;
    reg        out_ready;

    wire        cmd_ready;
    wire        in_ready;
    wire        out_valid;
    wire [7:0]  out_data;
    wire        busy;
    wire        key_valid;

    camellia128_epsiron dut (
        .clk       (clk),
        .rst       (rst),
        .cmd_valid (cmd_valid),
        .cmd_ready (cmd_ready),
        .cmd_op    (cmd_op),
        .in_valid  (in_valid),
        .in_ready  (in_ready),
        .in_data   (in_data),
        .out_valid (out_valid),
        .out_ready (out_ready),
        .out_data  (out_data),
        .busy      (busy),
        .key_valid (key_valid)
    );

    // ---------------- trace dump (same format as camellia_ref.py) ----------
    function [47:0] phase_name;
        input [3:0] ph;
        begin
            case (ph)
                4'd0: phase_name = "IDLE  ";
                4'd1: phase_name = "LOAD  ";
                4'd2: phase_name = "FRND  ";
                4'd3: phase_name = "FLA_L ";
                4'd4: phase_name = "FLB_L ";
                4'd5: phase_name = "FLB_R ";
                4'd6: phase_name = "FLA_R ";
                4'd7: phase_name = "KXOR  ";
                4'd8: phase_name = "KSTORE";
                4'd9: phase_name = "OUT   ";
                default: phase_name = "????  ";
            endcase
        end
    endfunction

    always @(negedge clk) begin
        #1;  // settle: let any zero-delay TB-side signal updates for this
             // same negedge event finish before sampling (avoids a race
             // with the handshake tasks below, which may set in_data/
             // in_valid/etc. at this exact simulation time).
        if (dut.u_ctrl.adv) begin
            $display(
                "%s cnt=%2d step=%2d dir=%1d rsel=%2d k=%02x x=%02x alu=%02x bus=%02x lanes=%04x %02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                phase_name(dut.u_ctrl.phase), dut.u_ctrl.cnt, dut.u_ctrl.step, dut.u_ctrl.dir,
                dut.u_ctrl.rsel, dut.u_dp.k, dut.u_dp.x, dut.u_dp.alu, dut.u_dp.bus, dut.u_ctrl.lane_en,
                dut.u_dp.st[0], dut.u_dp.st[1], dut.u_dp.st[2], dut.u_dp.st[3],
                dut.u_dp.st[4], dut.u_dp.st[5], dut.u_dp.st[6], dut.u_dp.st[7],
                dut.u_dp.st[8], dut.u_dp.st[9], dut.u_dp.st[10], dut.u_dp.st[11],
                dut.u_dp.st[12], dut.u_dp.st[13], dut.u_dp.st[14], dut.u_dp.st[15]);
        end
    end

    // ---------------- handshake tasks (see tb_camellia128_epsiron.v for the
    // negedge-checkpoint / no-blocking-clear-at-posedge rationale) ----------
    task send_cmd;
        input [1:0] op;
        begin
            cmd_op    = op;
            cmd_valid = 1'b1;
            while (!cmd_ready) begin
                @(posedge clk);
                @(negedge clk);
            end
            @(posedge clk);
            @(negedge clk);
            cmd_valid = 1'b0;
        end
    endtask

    task send_byte;
        input [7:0] data;
        begin
            in_data  = data;
            in_valid = 1'b1;
            while (!in_ready) begin
                @(posedge clk);
                @(negedge clk);
            end
            @(posedge clk);
            @(negedge clk);
            in_valid = 1'b0;
        end
    endtask

    task recv_byte;
        output [7:0] data;
        begin
            out_ready = 1'b1;
            while (!out_valid) begin
                @(posedge clk);
                @(negedge clk);
            end
            data = out_data;
            @(posedge clk);
            @(negedge clk);
            out_ready = 1'b0;
        end
    endtask

    task do_key;
        input [127:0] key;
        integer i;
        begin
            send_cmd(OP_KEY);
            for (i = 0; i < 16; i = i + 1)
                send_byte(key[127 - 8*i -: 8]);
            while (busy) @(negedge clk);
        end
    endtask

    task do_crypt;
        input          dec;
        input  [127:0] din;
        output [127:0] dout;
        integer  i;
        reg [7:0] b;
        begin
            send_cmd(dec ? OP_DEC : OP_ENC);
            for (i = 0; i < 16; i = i + 1)
                send_byte(din[127 - 8*i -: 8]);
            dout = 128'h0;
            for (i = 0; i < 16; i = i + 1) begin
                recv_byte(b);
                dout = (dout << 8) | b;
            end
            while (busy) @(negedge clk);
        end
    endtask

    reg [127:0] key, pt, result;
    reg [8*8-1:0] mode_str;
    integer       dec, code, i9;

    initial begin
        rst       = 1'b1;
        cmd_valid = 1'b0;
        cmd_op    = OP_KEY;
        in_valid  = 1'b0;
        in_data   = 8'h00;
        out_ready = 1'b0;

        repeat (2) @(negedge clk);
        rst = 1'b0;
        @(negedge clk);

        // Debug-only poke, for this trace-comparison harness alone: the
        // state register st[] has no reset in real hardware (spec 8.1/8.2,
        // required for LUTRAM inference), so its content is undefined until
        // first written. model/camellia_ref.py's Core instead starts with
        // S=[0]*16. Zero it here so the very first command's trace lines
        // (whose not-yet-written state bytes would otherwise show as 'x')
        // line up exactly with the model for a byte-for-byte diff.
        for (i9 = 0; i9 < 16; i9 = i9 + 1) dut.u_dp.st[i9] = 8'h00;

        key = 128'h0123456789abcdeffedcba9876543210;
        pt  = 128'h0123456789abcdeffedcba9876543210;
        mode_str = "enc";
        code = $value$plusargs("KEY=%h", key);
        code = $value$plusargs("PT=%h", pt);
        code = $value$plusargs("MODE=%s", mode_str);
        dec  = (mode_str == "dec");

        do_key(key);
        do_crypt(dec, pt, result);

        $display("RESULT %032x", result);
        $finish;
    end

endmodule
