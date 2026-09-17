module Requester #(
    parameter int ADDR_WIDTH      = 32,
    parameter int DATA_WIDTH      = 32,
    parameter bit WAKEUP_EN       = 1,
    parameter int USER_REQ_WIDTH  = 1,
    parameter int USER_DATA_WIDTH = 1,
    parameter int USER_RESP_WIDTH = 1,
    parameter bit Check_Type      = 1
)
(
    input  logic                            PCLK,
    input  logic                            PRESETn,

    
    ///////////////////////////////////////////////////////
    //////////////// UPSTREAM INTERFACE SIGNALS ///////////
    ///////////////////////////////////////////////////////    
    input  logic                            i_valid,
    input  logic [ADDR_WIDTH - 1 : 0]       i_addr,
    input  logic [2:0]                      i_prot,
    input  logic                            i_write,
    input  logic [DATA_WIDTH - 1 : 0]       i_wdata,
    input  logic [DATA_WIDTH/8 - 1 : 0]     i_strb,
    input  logic [USER_REQ_WIDTH - 1 : 0]   i_auser,
    input  logic [USER_DATA_WIDTH - 1 : 0]  i_wuser,

    output logic                            o_ready,
    output logic [DATA_WIDTH - 1 : 0]       o_rdata,
    output logic                            o_slverr,
    output logic [USER_RESP_WIDTH - 1 : 0]  o_buser,
    output logic [USER_DATA_WIDTH - 1 : 0]  o_ruser,

    
    ///////////////////////////////////////////////////////
    //////////////// APB_REQUESTER <--> INTERCONNECT///////
    ///////////////  APB_REQUESTER ---> COMPLETER /////////
    ///////////////////////////////////////////////////////       
    input  logic [DATA_WIDTH - 1 : 0]       PRDATA,  
    input  logic                            PREADY,  
    input  logic                            PSLVERR, 
    input  logic [USER_RESP_WIDTH - 1 : 0]  PBUSER,  
    input  logic [USER_DATA_WIDTH - 1 : 0]  PRUSER,  

    output logic [ADDR_WIDTH - 1 : 0]       PADDR,   
    output logic [2:0]                      PPROT,   
    output logic                            PSEL,    
    output logic                            PENABLE, 
    output logic                            PWRITE,
    output logic [DATA_WIDTH - 1 : 0]       PWDATA,
    output logic [DATA_WIDTH/8 - 1 : 0]     PSTRB,
    output logic                            PWAKEUP,
    output logic [USER_REQ_WIDTH - 1 : 0]   PAUSER,
    output logic [USER_DATA_WIDTH - 1 : 0]  PWUSER,

    ///////////////////////////////////////////////////////
    //////////////// INTERFACE PARITY PROTECTION //////////
    ///////////////////////////////////////////////////////     
    input  logic                                    PREADYCHK,
    input  logic [(DATA_WIDTH + 7)/8 - 1 : 0]       PRDATACHK,
    input  logic                                    PSLVERRCHK,
    input  logic [(USER_DATA_WIDTH + 7)/8 - 1 : 0]  PRUSERCHK,
    input  logic [(USER_RESP_WIDTH + 7)/8 - 1 : 0]  PBUSERCHK,
    output logic                                    o_parity_err,

    output logic [(ADDR_WIDTH + 7)/8 - 1 : 0]       PADDRCHK,
    output logic                                    PSELCHK,
    output logic                                    PENABLECHK,
    output logic [(DATA_WIDTH + 7)/8 - 1 : 0]       PWDATACHK,
    output logic                                    PSTRBCHK,
    output logic                                    PWAKEUPCHK,
    output logic [(USER_REQ_WIDTH + 7)/8 - 1 : 0]   PAUSERCHK,
    output logic [(USER_DATA_WIDTH + 7)/8 - 1 : 0]  PWUSERCHK,
    output logic                                    PCTRLCHK
);

    typedef enum logic [1:0] {
        IDLE   = 2'b00,
        SETUP  = 2'b01,
        ACCESS = 2'b10
    } state_e;

    state_e Current_State, Next_State;

    ///////////////////////////////////////////////////////
    ///////////////// FSM LOGIC ///////////////////////////
    ///////////////////////////////////////////////////////

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            Current_State <= IDLE;
        end else begin
            Current_State <= Next_State;
        end
    end

    always_comb begin
        case (Current_State)
            IDLE: begin
                if (i_valid) begin
                    Next_State = SETUP;
                end else begin
                    Next_State = IDLE;
                end
            end
            SETUP: begin
                Next_State = ACCESS;
            end
            ACCESS: begin
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
    always_comb begin
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        o_ready = 1'b0;

        case (Current_State)
            IDLE: begin
                o_ready = 1'b1;
            end
            SETUP: begin
                PSEL = 1'b1;
            end
            ACCESS: begin
                PSEL    = 1'b1;
                PENABLE = 1'b1;
                o_ready = PREADY;
            end
            default: begin
                PSEL    = 1'b0;
                PENABLE = 1'b0;
                o_ready = 1'b1;
            end
        endcase
    end

    ///////////////////////////////////////////////////////
    ///////////////// TRANSFERRED DATA ////////////////////
    ///////////////////////////////////////////////////////
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            PADDR  <= '0;
            PPROT  <= '0;
            PWRITE <= '0;
            PWDATA <= '0;
            PSTRB  <= '0;
            PAUSER <= '0;
            PWUSER <= '0;
        end else begin
            if (o_ready && i_valid) begin
                PADDR  <= i_addr;
                PPROT  <= i_prot;
                PWRITE <= i_write;
                PWDATA <= i_wdata;
                PSTRB  <= i_write ? i_strb : '0;
                PAUSER <= i_auser;
                PWUSER <= i_wuser;
            end
        end
    end

    assign o_rdata  = PRDATA;
    assign o_buser  = PBUSER;
    assign o_ruser  = PRUSER;
    assign o_slverr = PSLVERR;
    assign PWAKEUP  = WAKEUP_EN ? (i_valid || (Current_State == SETUP) || (Current_State == ACCESS)) : 1'b0;

    ///////////////////////////////////////////////////////
    ///////////// INTERFACE PARITY PROTECTION /////////////
    ///////////////////////////////////////////////////////
    logic [3:0] ctrl_payload;
    assign ctrl_payload = {PWRITE, PPROT};

    logic [4:0] check_errors;

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

            APB_parity_check #(.WIDTH(1), .GRAN(1)) u_pready_chk (
                .payload      (PREADY),
                .sent_check   (PREADYCHK),
                .Check_Enable (PSEL & PENABLE),
                .error        (check_errors[0])
            );

            APB_parity_check #(.WIDTH(DATA_WIDTH), .GRAN(8)) u_rdata_chk (
                .payload      (PRDATA),
                .sent_check   (PRDATACHK),
                .Check_Enable (PSEL & PENABLE & PREADY & !PWRITE),
                .error        (check_errors[1])
            );

            APB_parity_check #(.WIDTH(1), .GRAN(1)) u_slverr_chk (
                .payload      (PSLVERR),
                .sent_check   (PSLVERRCHK),
                .Check_Enable (PSEL & PENABLE & PREADY),
                .error        (check_errors[2])
            );

            APB_parity_check #(.WIDTH(USER_DATA_WIDTH), .GRAN(8)) u_ruser_chk (
                .payload      (PRUSER),
                .sent_check   (PRUSERCHK),
                .Check_Enable (PSEL & PENABLE & PREADY & !PWRITE),
                .error        (check_errors[3])
            );

            APB_parity_check #(.WIDTH(USER_RESP_WIDTH), .GRAN(8)) u_buser_chk (
                .payload      (PBUSER),
                .sent_check   (PBUSERCHK),
                .Check_Enable (PSEL & PENABLE & PREADY),
                .error        (check_errors[4])
            );

            assign o_parity_err = |check_errors;

        end else begin : g_parity_disabled
            assign PADDRCHK     = '0;
            assign PCTRLCHK     = 1'b0;
            assign PSELCHK      = 1'b0;
            assign PENABLECHK   = 1'b0;
            assign PWDATACHK    = '0;
            assign PSTRBCHK     = 1'b0;
            assign PWAKEUPCHK   = 1'b0;
            assign PAUSERCHK    = '0;
            assign PWUSERCHK    = '0;
            assign o_parity_err = 1'b0;
            assign check_errors = '0;
        end
    endgenerate

endmodule