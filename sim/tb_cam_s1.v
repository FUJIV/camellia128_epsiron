`default_nettype none
//
// tb_cam_s1 -- T1: cam_s1 standalone, all 256 inputs vs tv/s1.hex
//
module tb_cam_s1;

    reg  [7:0] a;
    wire [7:0] d;

    cam_s1 dut (.a(a), .d(d));

    reg [7:0] expect_mem [0:255];
    integer i;
    integer errors;

    initial begin
        $readmemh("tv/s1.hex", expect_mem);
        errors = 0;
        for (i = 0; i < 256; i = i + 1) begin
            a = i[7:0];
            #1;
            if (d !== expect_mem[i]) begin
                $display("MISMATCH a=%02x got=%02x expect=%02x", a, d, expect_mem[i]);
                errors = errors + 1;
            end
        end
        if (errors == 0) begin
            $display("PASS");
        end else begin
            $display("FAIL %0d", errors);
        end
        $finish;
    end

endmodule
