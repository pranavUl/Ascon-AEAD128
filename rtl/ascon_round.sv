module ascon_round (

    input  logic [63:0] X0_IN,
    input  logic [63:0] X1_IN,
    input  logic [63:0] X2_IN,
    input  logic [63:0] X3_IN,
    input  logic [63:0] X4_IN,
    input  logic [3:0]  ROUND_INDEX,

    output logic [63:0] X0_OUT,
    output logic [63:0] X1_OUT,
    output logic [63:0] X2_OUT,
    output logic [63:0] X3_OUT,
    output logic [63:0] X4_OUT

);

    logic [63:0] x0, x1, x2, x3, x4;

    logic [7:0] constant;

    logic [63:0] t0, t1, t2, t3, t4;

    always_comb begin : round_logic
        
        x0 = X0_IN;
        x1 = X1_IN;
        x2 = X2_IN;
        x3 = X3_IN;
        x4 = X4_IN;



        constant = {4'hF - ROUND_INDEX, ROUND_INDEX};
        x2[7:0] ^= constant;


        // SUBSTITUTION BOX
        x0 ^= x4;   
        x4 ^= x3;   
        x2 ^= x1;

        t0 = ~x0 & x1;  
        t1 = ~x1 & x2;  
        t2 = ~x2 & x3;  
        t3 = ~x3 & x4;  
        t4 = ~x4 & x0;
        
        
        x0 ^= t1;   
        x1 ^= t2;   
        x2 ^= t3;   
        x3 ^= t4;   
        x4 ^= t0;
        
        x1 ^= x0;   
        x0 ^= x4;   
        x3 ^= x2;
        
        x2 = ~x2;

        
        // linear diffusion

        x0 = x0 ^ {x0[18:0], x0[63:19]} ^ {x0[27:0], x0[63:28]};
        x1 = x1 ^ {x1[60:0], x1[63:61]} ^ {x1[38:0], x1[63:39]};
        x2 = x2 ^ {x2[0:0], x2[63:1]} ^ {x2[5:0], x2[63:6]};
        x3 = x3 ^ {x3[9:0], x3[63:10]} ^ {x3[16:0], x3[63:17]};
        x4 = x4 ^ {x4[6:0], x4[63:7]} ^ {x4[40:0], x4[63:41]};


        // final outputs
        X0_OUT = x0;
        X1_OUT = x1;
        X2_OUT = x2;
        X3_OUT = x3;
        X4_OUT = x4;

    end

endmodule
