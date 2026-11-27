module ascon_core (

    input  logic         clk,
    input  logic         reset,

    input  logic         START,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic         DECRYPT,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [127:0] KEY,
    input  logic [127:0] NONCE,

    input  logic         BDI_VALID,
    output logic         BDI_READY,
    
    input  logic [127:0] BDI,
    input  logic [4:0]   BDI_BYTES,
    input  logic         BDI_TYPE_AD,
    input  logic         BDI_LAST,

    output logic         BDO_VALID,
    input  logic         BDO_READY,
    output logic [127:0] BDO,
    output logic [4:0]   BDO_BYTES,

    output logic         TAG_VALID,
    output logic [127:0] TAG,
    output logic         BUSY

);

    typedef enum logic [3:0] {
        IDLE, INIT, AD_WAIT, AD_STIR, PT_WAIT, PT_STIR, FINAL, FINAL_PERM, TAG_OUT
    } phase_e;

    phase_e phase_q;

    logic [127:0] key_q; //, nonce_q; // latched at start
    logic pad_pending_q;   // if AD/PT ended flush on 16, need one all-pad block

    logic [127:0] bdi_padded;
    assign bdi_padded = BDI | (128'h1 << {BDI_BYTES, 3'b000}); // 16 byte or not


    logic [63:0] absorb_x0, absorb_x1;
    assign absorb_x0 = p_x0_in ^ bdi_padded[63:0];
    assign absorb_x1 = p_x1_in ^ bdi_padded[127:64];

    logic [127:0] bdo_q;
    logic [4:0] bdo_bytes_q;
    logic bdo_valid_q;

    logic [127:0] tag_q;
    logic tag_valid_q;



    // to drive permutation
    logic p_start, p_rounds_12;
    logic [63:0] p_x0_in, p_x1_in, p_x2_in, p_x3_in, p_x4_in;
    // permutation outputs
    logic perm_busy, perm_done;
    logic [63:0] perm_x0, perm_x1, perm_x2, perm_x3, perm_x4;

    ascon_permutation u_ascon_permutation (
        .clk           (clk),
        .reset         (reset),
        .START         (p_start),
        .NUM_ROUNDS_12 (p_rounds_12),
        .X0_IN         (p_x0_in),
        .X1_IN         (p_x1_in),
        .X2_IN         (p_x2_in),
        .X3_IN         (p_x3_in),
        .X4_IN         (p_x4_in),
        .BUSY          (perm_busy),
        .DONE          (perm_done),
        .X0_OUT        (perm_x0),
        .X1_OUT        (perm_x1),
        .X2_OUT        (perm_x2),
        .X3_OUT        (perm_x3),
        .X4_OUT        (perm_x4)
    );


    assign BDI_READY = !perm_busy && !p_start && !bdo_valid_q && ( // account for start state before busy signal raised
                        ((phase_q == AD_WAIT) &&  BDI_TYPE_AD) ||
                        ((phase_q == PT_WAIT) && !BDI_TYPE_AD));
                        // notes BDI READY necessary to apply backpressure to producer


    assign BDO = bdo_q;
    assign BDO_BYTES = bdo_bytes_q;
    assign BDO_VALID = bdo_valid_q;

    assign TAG = tag_q;
    assign TAG_VALID = tag_valid_q;
    assign BUSY = (phase_q != IDLE) && (phase_q != TAG_OUT);

    always_ff @(posedge clk) begin : core_fsm
        
        if (reset) begin
            phase_q <= IDLE;
            p_start <= 1'b0;

            pad_pending_q <= 1'b0;

            bdo_valid_q <= 1'b0;

            tag_valid_q <= 1'b0;
        end 
        
        else begin
            p_start <= 1'b0;   // default: START is a 1 cycle pulse
            
            if (BDO_READY) bdo_valid_q <= 1'b0; // transfer done

            case (phase_q)

                IDLE, TAG_OUT: begin
                    if (START) begin
                        key_q   <= KEY;
                        //nonce_q <= NONCE;
                        p_x0_in <= 64'h0000_1000_808C_0001;
                        p_x1_in <= KEY[63:0];
                        p_x2_in <= KEY[127:64];
                        p_x3_in <= NONCE[63:0];
                        p_x4_in <= NONCE[127:64];
                        p_rounds_12 <= 1'b1;
                        p_start <= 1'b1;
                        phase_q <= INIT;

                        tag_valid_q <= 1'b0;

                    end
                end

                INIT: begin
                    // wait for perm_done then do the key XOR
                    if (perm_done) begin
                        p_x0_in <= perm_x0;
                        p_x1_in <= perm_x1;
                        p_x2_in <= perm_x2;
                        p_x3_in <= perm_x3 ^ key_q[63:0];
                        p_x4_in <= perm_x4 ^ key_q[127:64];
                        phase_q <= AD_WAIT;
                    end
                end

                AD_WAIT: begin
                    if (BDI_VALID && BDI_READY) begin   // handshake here
                        p_x0_in <= p_x0_in ^ bdi_padded[63:0];
                        p_x1_in <= p_x1_in ^ bdi_padded[127:64];
                        p_rounds_12 <= 1'b0;
                        p_start <= 1'b1;
                        pad_pending_q <= (BDI_LAST && (BDI_BYTES == 5'd16)); // need extra pad
                        phase_q <= AD_STIR;
                    end
                    else if (BDI_VALID && !BDI_TYPE_AD) begin
                        // associated data over - flipping indicator bit (top of x4)
                        p_x4_in <= p_x4_in ^ (64'h1 << 63);
                        phase_q <= PT_WAIT;
                    end
                end

                AD_STIR: begin
                    if (perm_done) begin
                        if (pad_pending_q) begin
                            p_x0_in <= perm_x0 ^ 64'h1;
                            p_x1_in <= perm_x1;
                            p_x2_in <= perm_x2;
                            p_x3_in <= perm_x3;
                            p_x4_in <= perm_x4;
                            p_rounds_12 <= 1'b0;
                            p_start <= 1'b1;
                            pad_pending_q <= 1'b0;
                        end
                        else begin
                            p_x0_in <= perm_x0;
                            p_x1_in <= perm_x1;
                            p_x2_in <= perm_x2;
                            p_x3_in <= perm_x3;
                            p_x4_in <= perm_x4;
                            phase_q <= AD_WAIT;
                        end
                    end
                end

                PT_WAIT: begin
                    if (BDI_VALID && BDI_READY) begin
                        
                        p_x0_in <= absorb_x0;
                        p_x1_in <= absorb_x1;

                        if (BDI_BYTES != 5'd0) begin
                            bdo_q <= {absorb_x1, absorb_x0};
                            bdo_bytes_q <= BDI_BYTES;
                            bdo_valid_q <= 1'b1;
                        end

                        if (!BDI_LAST || (BDI_BYTES == 5'd16)) begin
                            p_rounds_12 <= 1'b0;
                            p_start <= 1'b1;
                            pad_pending_q <= (BDI_LAST && (BDI_BYTES == 5'd16));
                            phase_q <= PT_STIR;
                        end

                        else begin
                            phase_q <= FINAL;
                        end
                    end
                end

                PT_STIR: begin
                    if (perm_done) begin
                        if (pad_pending_q) begin
                            p_x0_in <= perm_x0 ^ 64'h1;
                            p_x1_in <= perm_x1;
                            p_x2_in <= perm_x2;
                            p_x3_in <= perm_x3;
                            p_x4_in <= perm_x4;
                            pad_pending_q <= 1'b0;
                            phase_q <= FINAL;
                        end
                        else begin
                            p_x0_in <= perm_x0;
                            p_x1_in <= perm_x1;
                            p_x2_in <= perm_x2;
                            p_x3_in <= perm_x3;
                            p_x4_in <= perm_x4;
                            phase_q <= PT_WAIT;
                        end
                    end
                end

                FINAL: begin
                    // IDLE/INIT
                    if (!bdo_valid_q) begin
                        p_x2_in <= p_x2_in ^ key_q[63:0];
                        p_x3_in <= p_x3_in ^ key_q[127:64];
                        p_rounds_12 <= 1'b1;
                        p_start <= 1'b1;
                        phase_q <= FINAL_PERM;
                    end
                end

                FINAL_PERM: begin
                    if (perm_done) begin
                        p_x0_in <= perm_x0;
                        p_x1_in <= perm_x1;
                        p_x2_in <= perm_x2;
                        p_x3_in <= perm_x3 ^ key_q[63:0];
                        p_x4_in <= perm_x4 ^ key_q[127:64];

                        tag_q <= {perm_x4 ^ key_q[127:64], perm_x3 ^ key_q[63:0]};
                        tag_valid_q <= 1'b1;

                        phase_q <= TAG_OUT;
                    end
                end

                default: ;
            endcase
        end

    end

endmodule
