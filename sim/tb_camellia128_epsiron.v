`default_nettype none
//
// tb_camellia128_epsiron -- functional testbench (T2-T8)
//
// Run from the project root so that relative paths (tv/*.hex) resolve:
//   xvlog src/cam_s1.v src/cam_dp.v src/cam_ctrl.v src/camellia128_epsiron.v sim/tb_camellia128_epsiron.v
//   xelab -s tb_snap work.tb_camellia128_epsiron
//   xsim tb_snap -runall [-testplusarg STALL] [-testplusarg TRACE]
//
// Plusargs:
//   +STALL  randomly deassert in_valid/out_ready (T5)
//   +TRACE  dump a per-cycle trace to sim_trace.log in the same format as
//           model/camellia_ref.py's `trace` command (for T9, see tb_trace.v)
//
module tb_camellia128_epsiron;

    localparam [1:0] OP_KEY = 2'd0, OP_ENC = 2'd1, OP_DEC = 2'd2, OP_RSV = 2'd3;
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

    integer errors;
    integer stall_mode;
    integer trace_en;
    integer trace_fd;

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

    // ---------------- +TRACE: per-cycle dump (same format as camellia_ref.py) --
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
        #1;  // settle: avoid racing the handshake tasks' zero-delay signal
             // updates at this same negedge (see tb_trace.v for detail)
        if (trace_en && dut.u_ctrl.adv) begin
            $fdisplay(trace_fd,
                "%s cnt=%2d step=%2d dir=%1d rsel=%2d k=%02x x=%02x alu=%02x bus=%02x lanes=%04x %02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                phase_name(dut.u_ctrl.phase), dut.u_ctrl.cnt, dut.u_ctrl.step, dut.u_ctrl.dir,
                dut.u_ctrl.rsel, dut.u_dp.k, dut.u_dp.x, dut.u_dp.alu, dut.u_dp.bus, dut.u_ctrl.lane_en,
                dut.u_dp.st[0], dut.u_dp.st[1], dut.u_dp.st[2], dut.u_dp.st[3],
                dut.u_dp.st[4], dut.u_dp.st[5], dut.u_dp.st[6], dut.u_dp.st[7],
                dut.u_dp.st[8], dut.u_dp.st[9], dut.u_dp.st[10], dut.u_dp.st[11],
                dut.u_dp.st[12], dut.u_dp.st[13], dut.u_dp.st[14], dut.u_dp.st[15]);
        end
    end

    // ---------------- stall helper (T5) ----------------
    task stall_cycles;
        integer k;
        begin
            if (stall_mode) begin
                k = $random;
                if (k < 0) k = -k;
                k = k % 3;
                repeat (k) @(negedge clk);
            end
        end
    endtask

    // ---------------- handshake tasks ----------------
    //
    // Invariant: every task below is entered AT a negedge checkpoint (where
    // all DUT combinational outputs -- *_ready/*_valid/busy -- are already
    // settled for the whole clock period that is about to end at the next
    // posedge), and returns AT a negedge checkpoint too. So readiness must be
    // checked immediately (zero delay) upon entry/after asserting valid --
    // NOT after an extra @(negedge clk), which would skip past the very
    // posedge that performs the transfer.
    //
    // Signals driven into the DUT must never be CLEARED with a blocking
    // assignment right after @(posedge clk): that write races against
    // cam_ctrl's own always@(posedge clk) block, which is sensitive to the
    // very same edge (undefined relative order between the two processes in
    // the same simulation delta-cycle). Clearing is therefore always
    // deferred to the following negedge checkpoint, which cannot race with
    // any posedge-triggered DUT process.
    task send_cmd;
        input [1:0] op;
        begin
            cmd_op    = op;
            cmd_valid = 1'b1;
            while (!cmd_ready) begin
                @(posedge clk);
                @(negedge clk);
            end
            @(posedge clk);          // transfer edge
            @(negedge clk);          // safe checkpoint (no race with cam_ctrl)
            cmd_valid = 1'b0;
        end
    endtask

    task send_byte;
        input [7:0] data;
        begin
            in_data = data;
            stall_cycles;
            in_valid = 1'b1;
            while (!in_ready) begin
                @(posedge clk);
                @(negedge clk);
            end
            @(posedge clk);          // transfer edge
            @(negedge clk);          // safe checkpoint
            in_valid = 1'b0;
        end
    endtask

    task recv_byte;
        output [7:0] data;
        begin
            stall_cycles;
            out_ready = 1'b1;
            while (!out_valid) begin
                @(posedge clk);
                @(negedge clk);
            end
            data = out_data;         // sample now: settled value for this period
            @(posedge clk);          // transfer edge
            @(negedge clk);          // safe checkpoint
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

    // ---------------- main test sequence ----------------
    reg [127:0] key, pt, ct, got_ct, got_pt, dout;
    reg [127:0] vkey, vpt, vct;
    reg [7:0]   t7_byte;
    integer     i, vcount, code, fd;
    time        t0;
    integer     cyc;

    initial begin
        #20000000 begin
            $display("WATCHDOG TIMEOUT at t=%0t phase=%0d cnt=%0d step=%0d busy=%b",
                $time, dut.u_ctrl.phase, dut.u_ctrl.cnt, dut.u_ctrl.step, busy);
            $finish;
        end
    end

    initial begin
        errors     = 0;
        stall_mode = 0;
        trace_en   = 0;
        rst        = 1'b1;
        cmd_valid  = 1'b0;
        cmd_op     = OP_KEY;
        in_valid   = 1'b0;
        in_data    = 8'h00;
        out_ready  = 1'b0;

        repeat (2) @(negedge clk);
        rst = 1'b0;
        @(negedge clk);

        stall_mode = $test$plusargs("STALL");
        trace_en   = $test$plusargs("TRACE");
        if (trace_en) trace_fd = $fopen("sim_trace.log", "w");

        // ---- T2: RFC 3713 vector ----
        key = 128'h0123456789abcdeffedcba9876543210;
        pt  = key;
        ct  = 128'h67673138549669730857065648eabe43;

        do_key(key);
        if (!key_valid) begin
            $display("T2 FAIL: key_valid not set after KEY");
            errors = errors + 1;
        end
        do_crypt(1'b0, pt, got_ct);
        if (got_ct !== ct) begin
            $display("T2 FAIL: enc got=%032x expect=%032x", got_ct, ct);
            errors = errors + 1;
        end else $display("T2 PASS: RFC3713 enc");
        do_crypt(1'b1, ct, got_pt);
        if (got_pt !== pt) begin
            $display("T2 FAIL: dec got=%032x expect=%032x", got_pt, pt);
            errors = errors + 1;
        end else $display("T2 PASS: RFC3713 dec");

        // ---- T6: cycle counts (no-stall runs only) ----
        // Measured as wall-clock simulation time elapsed, divided by the
        // clock period -- immune to the register-update races that a
        // DUT-side "busy cycle counter" sampled via $display would hit.
        // The window starts right after send_cmd() returns (i.e. the cycle
        // right after command acceptance, where LOAD begins) and ends right
        // after the final "while(busy)" settles (phase back to IDLE), per
        // spec 10.1: "LOAD開始からIDLE復帰まで".
        if (!stall_mode) begin
            send_cmd(OP_KEY);
            t0 = $time;
            for (i = 0; i < 16; i = i + 1) send_byte(key[127 - 8*i -: 8]);
            while (busy) @(negedge clk);
            cyc = ($time - t0) / CLK_PERIOD;
            if (cyc !== 80) begin
                $display("T6 FAIL: KEY cycles=%0d expect 80", cyc);
                errors = errors + 1;
            end else $display("T6 PASS: KEY=80 cycles");

            send_cmd(OP_ENC);
            t0 = $time;
            for (i = 0; i < 16; i = i + 1) send_byte(pt[127 - 8*i -: 8]);
            got_ct = 128'h0;
            for (i = 0; i < 16; i = i + 1) begin
                recv_byte(t7_byte);
                got_ct = (got_ct << 8) | t7_byte;
            end
            while (busy) @(negedge clk);
            cyc = ($time - t0) / CLK_PERIOD;
            if (cyc !== 212) begin
                $display("T6 FAIL: ENC cycles=%0d expect 212", cyc);
                errors = errors + 1;
            end else $display("T6 PASS: ENC=212 cycles");

            send_cmd(OP_DEC);
            t0 = $time;
            for (i = 0; i < 16; i = i + 1) send_byte(ct[127 - 8*i -: 8]);
            got_pt = 128'h0;
            for (i = 0; i < 16; i = i + 1) begin
                recv_byte(t7_byte);
                got_pt = (got_pt << 8) | t7_byte;
            end
            while (busy) @(negedge clk);
            cyc = ($time - t0) / CLK_PERIOD;
            if (cyc !== 212) begin
                $display("T6 FAIL: DEC cycles=%0d expect 212", cyc);
                errors = errors + 1;
            end else $display("T6 PASS: DEC=212 cycles");
        end

        // ---- T4: multiple blocks per key (no rekey), then change key ----
        do_key(key);
        do_crypt(1'b0, pt, got_ct);
        if (got_ct !== ct) begin
            $display("T4 FAIL: block1");
            errors = errors + 1;
        end
        do_crypt(1'b0, pt, got_ct);   // same key, second block, no re-key
        if (got_ct !== ct) begin
            $display("T4 FAIL: block2 (no rekey)");
            errors = errors + 1;
        end
        do_key(128'h0);
        do_crypt(1'b0, 128'h0, got_ct);
        if (got_ct !== 128'h3d028025b156327c17f762c1f2cbca71) begin
            $display("T4 FAIL: after key change got=%032x", got_ct);
            errors = errors + 1;
        end else $display("T4 PASS");

        // ---- T7: cmd rejected while busy ----
        do_key(key);
        send_cmd(OP_ENC);
        for (i = 0; i < 16; i = i + 1) begin
            send_byte(pt[127 - 8*i -: 8]);
            if (i == 3) begin
                // we are at a negedge checkpoint here (just returned from
                // send_byte); cmd_ready is already settled for this period.
                cmd_valid = 1'b1;
                cmd_op    = OP_KEY;
                if (cmd_ready !== 1'b0) begin
                    $display("T7 FAIL: cmd_ready=1 while busy");
                    errors = errors + 1;
                end
                @(posedge clk);   // let the DUT actually sample cmd_valid=1 while busy
                @(negedge clk);
                cmd_valid = 1'b0;
            end
        end
        dout = 128'h0;
        for (i = 0; i < 16; i = i + 1) begin
            recv_byte(t7_byte);
            dout = (dout << 8) | t7_byte;
        end
        while (busy) @(negedge clk);
        if (dout !== ct) begin
            $display("T7 FAIL: result corrupted by spurious cmd, got=%032x", dout);
            errors = errors + 1;
        end else $display("T7 PASS: cmd_ready=0 while busy, result intact");

        // ---- T8: rst mid-processing ----
        send_cmd(OP_ENC);
        for (i = 0; i < 5; i = i + 1)
            send_byte(pt[127 - 8*i -: 8]);
        repeat (3) @(negedge clk);
        rst = 1'b1;
        @(negedge clk);
        if (busy !== 1'b0) begin
            $display("T8 FAIL: busy=1 after rst");
            errors = errors + 1;
        end
        if (key_valid !== 1'b0) begin
            $display("T8 FAIL: key_valid=1 after rst");
            errors = errors + 1;
        end
        @(posedge clk);
        @(negedge clk);
        rst       = 1'b0;
        in_valid  = 1'b0;
        out_ready = 1'b0;
        cmd_valid = 1'b0;
        @(negedge clk);
        do_key(key);
        do_crypt(1'b0, pt, got_ct);
        if (got_ct !== ct) begin
            $display("T8 FAIL: post-rst enc mismatch got=%032x", got_ct);
            errors = errors + 1;
        end else $display("T8 PASS");

        // ---- T3 / T5: all vectors in tv/vectors.hex ----
        fd = $fopen("tv/vectors.hex", "r");
        if (fd == 0) begin
            $display("ERROR: cannot open tv/vectors.hex");
            errors = errors + 1;
        end else begin
            vcount = 0;
            code = $fscanf(fd, "%h %h %h", vkey, vpt, vct);
            while (code == 3) begin
                vcount = vcount + 1;
                do_key(vkey);
                do_crypt(1'b0, vpt, got_ct);
                if (got_ct !== vct) begin
                    $display("T3 FAIL vec#%0d enc got=%032x expect=%032x", vcount, got_ct, vct);
                    errors = errors + 1;
                end
                do_crypt(1'b1, vct, got_pt);
                if (got_pt !== vpt) begin
                    $display("T3 FAIL vec#%0d dec got=%032x expect=%032x", vcount, got_pt, vpt);
                    errors = errors + 1;
                end
                code = $fscanf(fd, "%h %h %h", vkey, vpt, vct);
            end
            $fclose(fd);
            $display("%s: ran %0d vectors", (stall_mode ? "T5" : "T3"), vcount);
        end

        if (trace_en) $fclose(trace_fd);

        if (errors == 0) $display("PASS");
        else $display("FAIL %0d", errors);
        $finish;
    end

endmodule
