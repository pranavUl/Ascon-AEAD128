module ascon_permutation (

    input  logic        clk,
    input  logic        reset,

    input  logic        START,
    input  logic        NUM_ROUNDS_12,
    input  logic [63:0] X0_IN,
    input  logic [63:0] X1_IN,
    input  logic [63:0] X2_IN,
    input  logic [63:0] X3_IN,
    input  logic [63:0] X4_IN,

    output logic        BUSY,
    output logic        DONE,
    output logic [63:0] X0_OUT,
    output logic [63:0] X1_OUT,
    output logic [63:0] X2_OUT,
    output logic [63:0] X3_OUT,
    output logic [63:0] X4_OUT

);


    // state + control regs
    logic [63:0] x0_q, x1_q, x2_q, x3_q, x4_q;
    logic [3:0] round_q;
    logic busy_q, done_q;

    logic [63:0] rnd_x0, rnd_x1, rnd_x2, rnd_x3, rnd_x4; // for ascon round

    ascon_round u_ascon_round (
        .X0_IN       (x0_q),
        .X1_IN       (x1_q),
        .X2_IN       (x2_q),
        .X3_IN       (x3_q),
        .X4_IN       (x4_q),
        .ROUND_INDEX (round_q),
        .X0_OUT      (rnd_x0),
        .X1_OUT      (rnd_x1),
        .X2_OUT      (rnd_x2),
        .X3_OUT      (rnd_x3),
        .X4_OUT      (rnd_x4)
    );

    always_ff @(posedge clk) begin : ctrl
        
        if (reset) begin
            busy_q <= 1'b0;
            done_q <= 1'b0;
        end 
        
        else if (START && !busy_q) begin
            
            // initialize all
            x0_q <= X0_IN;
            x1_q <= X1_IN;
            x2_q <= X2_IN;
            x3_q <= X3_IN;
            x4_q <= X4_IN;

            if (NUM_ROUNDS_12) 
                round_q <= 4'd0;
            else
                round_q <= 4'd4;

            busy_q  <= 1'b1;
            done_q  <= 1'b0;
            
        end 
        
        else if (busy_q) begin

            x0_q <= rnd_x0;
            x1_q <= rnd_x1;
            x2_q <= rnd_x2;
            x3_q <= rnd_x3;
            x4_q <= rnd_x4;

            round_q <= round_q + 4'd1;
            
            if (round_q == 4'd11) begin
                busy_q <= 1'b0;
                done_q <= 1'b1;
            end

        end 
        
        else begin
            done_q <= 1'b0;
        end
    end

    assign BUSY = busy_q;
    assign DONE = done_q;
    assign X0_OUT = x0_q;
    assign X1_OUT = x1_q;
    assign X2_OUT = x2_q;
    assign X3_OUT = x3_q;
    assign X4_OUT = x4_q;

endmodule
