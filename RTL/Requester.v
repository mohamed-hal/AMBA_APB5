module Requester #(
    parameter ADDR_WIDTH      = 32,
    parameter DATA_WIDTH      = 32,
    parameter WAKEUP_EN       = 1,
    parameter USER_REQ_WIDTH  = 1,
    parameter USER_DATA_WIDTH = 1,
    parameter USER_RESP_WIDTH = 1,
    parameter Check_Type      = 1 
)  
(
    input    wire                           PCLK,
    input    wire                           PRESETn,

    // UPSTREAM INTERFACE SIGNALS
    input    wire                           i_valid,
    input    wire [ADDR_WIDTH - 1 : 0]      i_addr,
    input    wire       [2:0]               i_prot,
    input    wire                           i_write,
    input    wire [DATA_WIDTH - 1 : 0]      i_wdata,
    input    wire [DATA_WIDTH/8 - 1 : 0]     i_strb,
    input    wire [USER_REQ_WIDTH - 1 : 0]  i_auser,
    input    wire [USER_DATA_WIDTH - 1 : 0] i_wuser,

    output   reg                            o_ready,
    output   wire [DATA_WIDTH - 1 : 0]      o_rdata,
    output   wire                           o_slvrr,
    output   wire [USER_RESP_WIDTH - 1 : 0] o_buser,
    output   wire [USER_DATA_WIDTH - 1 : 0] o_ruser,

    // APB_REQUESTER <--------------> INTERCONNECT
    input    wire [DATA_WIDTH - 1 : 0]      PRDATA,
    input    wire                           PREADY,
    input    wire                           PSLVERR,
    input    wire [USER_RESP_WIDTH - 1 : 0] PBUSER,
    input    wire [USER_DATA_WIDTH - 1 : 0] PRUSER,

    output   reg  [ADDR_WIDTH - 1 : 0]      PADDR,
    output   reg       [2:0]                PPROT,
    output   reg                            PSEL,
    output   reg                            PENABLE,
    output   reg                            PWRITE,
    output   reg  [DATA_WIDTH - 1 : 0]      PWDATA,
    output   reg  [DATA_WIDTH/8 - 1 :0]     PSTRB,
    output   wire                           PWAKEUP,
    output   reg  [USER_REQ_WIDTH - 1 : 0]  PAUSER,
    output   reg  [USER_DATA_WIDTH - 1 : 0] PWUSER,

    // INTERFACE PARITY PROTECTION —
    input    wire                                   PREADYCHK,
    input    wire [(DATA_WIDTH + 7)/8 - 1 : 0]      PRDATACHK,
    input    wire                                   PSLVERRCHK,
    input    wire [(USER_DATA_WIDTH + 7)/8 - 1 : 0] PRUSERCHK,
    input    wire [(USER_RESP_WIDTH + 7)/8 - 1 : 0] PBUSERCHK,
    output   wire                                   o_parity_err,

    output   wire [(ADDR_WIDTH + 7)/8 - 1 : 0]      PADDRCHK,
    output   wire                                   PSELCHK,
    output   wire                                   PENABLECHK,
    output   wire [(DATA_WIDTH + 7)/8 - 1 : 0]      PWDATACHK,
    output   wire                                   PSTRBCHK,
    output   wire                                   PWAKEUPCHK,
    output   wire [(USER_REQ_WIDTH + 7)/8 - 1 : 0]  PAUSERCHK,
    output   wire [(USER_DATA_WIDTH + 7)/8 - 1 : 0] PWUSERCHK,
    output   wire                                   PCTRLCHK
    );

    localparam IDLE   = 2'b00,
               SETUP  = 2'b01,
               ACCESS = 2'b10;

    reg [1:0] Current_State, Next_State;

    ///////////////////////////////////////////////////////
    ///////////////// FSM LOGIC ///////////////////////////
    ///////////////////////////////////////////////////////

    always @(posedge PCLK , negedge PRESETn) begin
        if (!PRESETn) begin
            Current_State <= IDLE;
        end else begin
            Current_State <= Next_State;
        end
    end

    always @(*) begin
        case (Current_State)
        IDLE    : begin
            if (i_valid) begin
                Next_State = SETUP;
            end else begin
                Next_State = IDLE;
            end
        end
        SETUP   : begin
            Next_State = ACCESS;
        end
        ACCESS  : begin
            if (PREADY) begin
                if (i_valid) begin
                    Next_State = SETUP;
                end else begin
                    Next_State = IDLE;
                end
            end else begin
                Next_State = ACCESS;
            end
        end
            default: begin
                Next_State = IDLE;
            end
        endcase
    end

    /////OUTPUT FSM LOGIC///////
    always @(*) begin
        PSEL    = 'd0;
        PENABLE = 'd0;
        o_ready = 'd0;

        case (Current_State)
        IDLE    : begin
            o_ready = 'd1;
        end
        SETUP   : begin
            PSEL = 'd1;
        end
        ACCESS  : begin
            PSEL    = 'd1;
            PENABLE = 'd1;
            o_ready = PREADY;
        end
            default: begin
                PSEL    = 'd0;
                PENABLE = 'd0;
                o_ready = 'd0;
            end
        endcase
    end

    ///////////////////////////////////////////////////////
    ///////////////// TRANSFERRED DATA ////////////////////
    ///////////////////////////////////////////////////////
    always @(posedge PCLK) begin
        if (o_ready && i_valid) begin
            PADDR   <= i_addr;
            PPROT   <= i_prot;
            PWRITE  <= i_write;
            PWDATA  <= i_wdata;
            PSTRB   <= i_write ? i_strb : 'd0;
            PAUSER  <= i_auser;
            PWUSER  <= i_wuser;
        end
    end

    assign o_rdata = PRDATA;
    assign o_buser = PBUSER;
    assign o_ruser = PRUSER;
    assign o_slvrr = PSLVERR;
    assign PWAKEUP = WAKEUP_EN ? (i_valid || (Current_State == SETUP) || (Current_State == ACCESS)) : 'd0;

    ///////////////////////////////////////////////////////
    ///////////// INTERFACE PARITY PROTECTION /////////////
    ///////////////////////////////////////////////////////
    wire [3:0] ctrl_payload = {PWRITE, PPROT};
    wire [4:0] check_errors;
    assign o_parity_err = |check_errors;

    generate
    if (Check_Type) begin : g_parity_enabled

        APB_parity_gen #(.WIDTH(ADDR_WIDTH), .GRAN(8)) u_addr_chk (
            .payload (PADDR),
            .chk     (PADDRCHK)
        );

        APB_parity_gen #(.WIDTH(4), .GRAN(4)) u_ctrl_chk (
            .payload (ctrl_payload),
            .chk     (PCTRLCHK)
        );

        APB_parity_gen #(.WIDTH(1), .GRAN(1)) u_sel_chk (
            .payload (PSEL),
            .chk     (PSELCHK)
        );

        APB_parity_gen #(.WIDTH(1), .GRAN(1)) u_enable_chk (
            .payload (PENABLE),
            .chk     (PENABLECHK)
        );

        APB_parity_gen #(.WIDTH(DATA_WIDTH), .GRAN(8)) u_wdata_chk (
            .payload (PWDATA),
            .chk     (PWDATACHK)
        );

        APB_parity_gen #(.WIDTH(DATA_WIDTH/8), .GRAN(DATA_WIDTH/8)) u_strb_chk (
            .payload (PSTRB),
            .chk     (PSTRBCHK)
        );

        APB_parity_gen #(.WIDTH(1), .GRAN(1)) u_wakeup_chk (
            .payload (PWAKEUP),
            .chk     (PWAKEUPCHK)
        );

        APB_parity_gen #(.WIDTH(USER_REQ_WIDTH), .GRAN(8)) u_auser_chk (
            .payload (PAUSER),
            .chk     (PAUSERCHK)
        );

        APB_parity_gen #(.WIDTH(USER_DATA_WIDTH), .GRAN(8)) u_wuser_chk (
            .payload (PWUSER),
            .chk     (PWUSERCHK)
        );

        APB_parity_check #(.WIDTH(1) , .GRAN(1)) u_pready_chk (
            .payload      (PREADY),
            .sent_check   (PREADYCHK),
            .Check_Enable (PSEL & PENABLE),
            .error        (check_errors[0])
        );

        APB_parity_check #(.WIDTH(DATA_WIDTH) , .GRAN(8)) u_rdata_chk (
            .payload      (PRDATA),
            .sent_check   (PRDATACHK),
            .Check_Enable (PSEL & PENABLE & PREADY & !PWRITE),
            .error        (check_errors[1])
        );

        APB_parity_check #(.WIDTH(1) , .GRAN(1)) u_slverr_chk (
            .payload      (PSLVERR),
            .sent_check   (PSLVERRCHK),
            .Check_Enable (PSEL & PENABLE & PREADY),
            .error        (check_errors[2])
        );

        APB_parity_check #(.WIDTH(USER_DATA_WIDTH) , .GRAN(8)) u_ruser_chk (
            .payload      (PRUSER),
            .sent_check   (PRUSERCHK),
            .Check_Enable (PSEL & PENABLE & PREADY & !PWRITE),
            .error        (check_errors[3])
        );

        APB_parity_check #(.WIDTH(USER_RESP_WIDTH) , .GRAN(8)) u_buser_chk (
            .payload      (PBUSER),
            .sent_check   (PBUSERCHK),
            .Check_Enable (PSEL & PENABLE & PREADY),
            .error        (check_errors[4])
        );                    

    end else begin : g_parity_disabled
        assign PADDRCHK     = {((ADDR_WIDTH + 7)/8){1'b0}};
        assign PCTRLCHK     = 1'b0;
        assign PSELCHK      = 1'b0;
        assign PENABLECHK   = 1'b0;
        assign PWDATACHK    = {((DATA_WIDTH + 7)/8){1'b0}};
        assign PSTRBCHK     = 1'b0;
        assign PWAKEUPCHK   = 1'b0;
        assign PAUSERCHK    = {((USER_REQ_WIDTH + 7)/8){1'b0}};
        assign PWUSERCHK    = {((USER_DATA_WIDTH + 7)/8){1'b0}};
        assign o_parity_err = 1'b0;
    end
    endgenerate

endmodule