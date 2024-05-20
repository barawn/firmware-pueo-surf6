`timescale 1ns / 1ps
// Sync up aclk/memclk.
// memclk_sync_o/aclk_sync_o both indicate the first clock phase.
// It does:
// tick memclk memclk_sync aclk aclk_sync
// 0    1      1           1    1
// 1    1      1           1    1
// 2    1      1           1    1
// 3    0      1           1    1
// 4    0      1           0    1
// 5    0      1           0    1
// 6    1      0           0    1
// 7    1      0           0    1
// 8    1      0           1    0
// 9    0      0           1    0
// etc.

// This is the v2 version, which hopefully handles resets
// better.
module pueo_clk_phase_v2(
        input aclk,
        input memclk,
        input syncclk,
        input locked_i,
        output memclk_sync_o,
        output aclk_sync_o,
        output syncclk_toggle_o
    );

    // the sync periods are period length so they line up.
    (* ASYNC_REG = "TRUE" *)
    reg [2:0] aclk_sync = 2'b00;
    (* ASYNC_REG = "TRUE" *)
    reg [3:0] memclk_sync = 3'b000;
    // detect aclk phase
    reg aclk_phase = 1'b0;
    // detect memclk phase
    reg memclk_phase = 1'b0;
    reg syncclk_toggle = 0;

    // OK LET'S TRACE OUT THE DELAYS
    // WE PRETEND THERE'S ONE TICK C-TO-Q
    // THIS IS STARTUP AFTER LOCKED GOES HIGH
    // aclk_phase is aclk_sync[2] ^ aclk_sync[1]
    // memclk_phase is memclk_sync[3] ^ memclk_sync[2]
    // tick memclk aclk syncclk toggle aclk_sync memclk_sync        aclk_phase
    // 23   0      0    0       0      000       0000               0
    // 0    1      1    1       0      000       0000   -- START    0
    // 1    1      1    1       1      000       0000               0
    // 2    1      1    1       1      000       0000               0
    // 3    0      1    1       1      000       0000               0
    // 4    0      0    1       1      000       0000               0
    // 5    0      0    1       1      000       0000               0
    // 6    1      0    1       1      000       0000               0
    // 7    1      0    1       1      000       0001               0
    // 8    1      1    1       1      000       0001               0
    // 9    0      1    1       1      001       0001               0
    // 10   0      1    1       1      001       0001               0
    // 11   0      1    1       1      001       0001               0
    // 12   1      0    0       1      001       0001               0
    // 13   1      0    0       1      001       0011               0
    // 14   1      0    0       1      001       0011               0
    // 15   0      0    0       1      001       0011               0
    // 16   0      1    0       1      001       0011               0
    // 17   0      1    0       1      011       0011               0
    // 18   1      1    0       1      011       0011               0
    // 19   1      1    0       1      011       0111               0
    // 20   1      0    0       1      011       0111               0
    // 21   0      0    0       1      011       0111               0
    // 22   0      0    0       1      011       0111               0
    // 23   0      0    0       1      011       0111               0
    // 0    1      1    1       1      011       0111   --- START   0
    // 1    1      1    1       0      111       1111               1
    // 2    1      1    1       0      111       1111               1
    // 3    0      1    1       0      111       1111               1
    // 4    0      0    1       0      111       1111               1
    // 5    0      0    1       0      111       1111               1
    // 6    1      0    1       0      111       1111               1
    // 7    1      0    1       0      111       1110               1
    // 8    1      1    1       0      111       1110               1
    // 9    0      1    1       0      110       1110               0
    // 10   0      1    1       0      110       1110               0
    // 11   0      1    1       0      110       1110               0
    // 12   1      0    0       0      110       1110               0
    // 13   1      0    0       0      110       1100               0
    // 14   1      0    0       0      110       1100               0
    // 15   0      0    0       0      110       1100               0
    // 16   0      1    0       0      110       1100               0
    // 17   0      1    0       0      100       1100               0
    // 18   1      1    0       0      100       1100               0
    // 19   1      1    0       0      100       1000               0
    // 20   1      0    0       0      100       1000               0
    // 21   0      0    0       0      100       1000               0
    // 22   0      0    0       0      100       1000               0
    // 23   0      0    0       0      100       1000               0
    // 0    1      1    1       0      100       1000   --- START   0
    // 1    1      1    1       1      000       0000               1

    // But it's got a bit more logic, so we buffer it by delaying it a full cycle. So the output here is a little slower to start up, but that's not a big deal.
    // clk memclk_phase memclk_phase_buf
    // 0   1         0000
    // 1   0010         0001
    // 2   0100         0010
    // 3   1000         0100
    // 4   0001         1000

    reg [3:0] memclk_phase_buf = {4{1'b0}};
    reg [2:0] aclk_phase_buf = {3{1'b0}};

    // don't start toggling until locked
    always @(posedge syncclk) begin
        if (!locked_i) syncclk_toggle <= 1'b0;
        else syncclk_toggle <= ~syncclk_toggle;
    end

    always @(posedge memclk) begin
        memclk_sync <= {memclk_sync[2:0], syncclk_toggle};        
        // indicates first clock phase
        memclk_phase <= memclk_sync[3] ^ memclk_sync[2];

        // buffer the thing
        // this is a 4 clock delay on memclk_phase
        // so memclk_phase_buf[3] = memclk_phase
        memclk_phase_buf <= {memclk_phase_buf[2:0], memclk_phase};
    end
    always @(posedge aclk) begin
        aclk_sync <= {aclk_sync[1:0], syncclk_toggle};
        // indicates first clock phase
        aclk_phase <= aclk_sync[2] ^ aclk_sync[1];    
    
        // buffer the thing
        // see above
        aclk_phase_buf <= {aclk_phase_buf[1:0], aclk_phase};
    end

    assign memclk_sync_o = memclk_phase_buf[3];
    assign aclk_sync_o = aclk_phase_buf[2];
        
    assign syncclk_toggle_o = syncclk_toggle;
endmodule
