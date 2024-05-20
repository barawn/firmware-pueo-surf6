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
module pueo_clk_phase(
        input aclk,
        input memclk,
        input syncclk,
        output memclk_sync_o,
        output aclk_sync_o,
        output syncclk_toggle_o
    );
    // the sync periods are period length so they line up.
    (* ASYNC_REG = "TRUE" *)
    reg [2:0] aclk_sync = 2'b00;
    (* ASYNC_REG = "TRUE" *)
    reg [3:0] memclk_sync = 3'b000;
    // aclk's period is 3 long
    reg [2:0] aclk_phase = {3{1'b0}};
    // memclk's period is 4 long
    reg [3:0] memclk_phase = {4{1'b0}};
    reg syncclk_toggle = 0;

    // memclk_phase[0] being high indicates the first phase
    // But it's got a bit more logic, so we buffer it by delaying it a full cycle. So the output here is a little slower to start up, but that's not a big deal.
    // clk memclk_phase memclk_phase_buf
    // 0   0001         0000
    // 1   0010         0001
    // 2   0100         0010
    // 3   1000         0100
    // 4   0001         1000

    reg [3:0] memclk_phase_buf = {4{1'b0}};
    reg [2:0] aclk_phase_buf = {3{1'b0}};

    always @(posedge syncclk) syncclk_toggle <= ~syncclk_toggle;
    always @(posedge memclk) begin
        memclk_sync <= {memclk_sync[2:0], syncclk_toggle};
        
        if (memclk_sync[2] && !memclk_sync[3]) memclk_phase <= 4'b0001;
        else memclk_phase <= {memclk_phase[2:0],memclk_phase[3]};

        memclk_phase_buf <= {memclk_phase_buf[2:0], memclk_phase[0]};
    end
    always @(posedge aclk) begin
        aclk_sync <= {aclk_sync[1:0], syncclk_toggle};
        
        if (aclk_sync[1] && !aclk_sync[2]) aclk_phase <= 3'b001;
        else aclk_phase <= {aclk_phase[1:0], aclk_phase[2]};
        
        aclk_phase_buf <= {aclk_phase_buf[1:0], aclk_phase[0]};
    end

    assign memclk_sync_o = memclk_phase_buf[3];
    assign aclk_sync_o = aclk_phase_buf[2];
        
    assign syncclk_toggle_o = syncclk_toggle;
endmodule
