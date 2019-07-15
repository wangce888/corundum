/*

Copyright (c) 2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`timescale 1ns / 1ps

/*
 * AXI4 DMA
 */
module axi_dma_rd #
(
    parameter AXI_DATA_WIDTH = 32,
    parameter AXI_ADDR_WIDTH = 16,
    parameter AXI_STRB_WIDTH = (AXI_DATA_WIDTH/8),
    parameter AXI_ID_WIDTH = 8,
    parameter AXI_MAX_BURST_LEN = 16,
    parameter AXIS_DATA_WIDTH = AXI_DATA_WIDTH,
    parameter AXIS_KEEP_ENABLE = (AXIS_DATA_WIDTH>8),
    parameter AXIS_KEEP_WIDTH = (AXIS_DATA_WIDTH/8),
    parameter AXIS_LAST_ENABLE = 1,
    parameter AXIS_ID_ENABLE = 0,
    parameter AXIS_ID_WIDTH = 8,
    parameter AXIS_DEST_ENABLE = 0,
    parameter AXIS_DEST_WIDTH = 8,
    parameter AXIS_USER_ENABLE = 1,
    parameter AXIS_USER_WIDTH = 1,
    parameter LEN_WIDTH = 20,
    parameter TAG_WIDTH = 8,
    parameter ENABLE_SG = 0,
    parameter ENABLE_UNALIGNED = 0
)
(
    input  wire                       clk,
    input  wire                       rst,

    /*
     * AXI read descriptor input
     */
    input  wire [AXI_ADDR_WIDTH-1:0]  s_axis_read_desc_addr,
    input  wire [LEN_WIDTH-1:0]       s_axis_read_desc_len,
    input  wire [TAG_WIDTH-1:0]       s_axis_read_desc_tag,
    input  wire [AXIS_ID_WIDTH-1:0]   s_axis_read_desc_id,
    input  wire [AXIS_DEST_WIDTH-1:0] s_axis_read_desc_dest,
    input  wire [AXIS_USER_WIDTH-1:0] s_axis_read_desc_user,
    input  wire                       s_axis_read_desc_valid,
    output wire                       s_axis_read_desc_ready,

    /*
     * AXI read descriptor status output
     */
    output wire [TAG_WIDTH-1:0]       m_axis_read_desc_status_tag,
    output wire                       m_axis_read_desc_status_valid,

    /*
     * AXI stream read data output
     */
    output wire [AXIS_DATA_WIDTH-1:0] m_axis_read_data_tdata,
    output wire [AXIS_KEEP_WIDTH-1:0] m_axis_read_data_tkeep,
    output wire                       m_axis_read_data_tvalid,
    input  wire                       m_axis_read_data_tready,
    output wire                       m_axis_read_data_tlast,
    output wire [AXIS_ID_WIDTH-1:0]   m_axis_read_data_tid,
    output wire [AXIS_DEST_WIDTH-1:0] m_axis_read_data_tdest,
    output wire [AXIS_USER_WIDTH-1:0] m_axis_read_data_tuser,

    /*
     * AXI master interface
     */
    output wire [AXI_ID_WIDTH-1:0]    m_axi_arid,
    output wire [AXI_ADDR_WIDTH-1:0]  m_axi_araddr,
    output wire [7:0]                 m_axi_arlen,
    output wire [2:0]                 m_axi_arsize,
    output wire [1:0]                 m_axi_arburst,
    output wire                       m_axi_arlock,
    output wire [3:0]                 m_axi_arcache,
    output wire [2:0]                 m_axi_arprot,
    output wire                       m_axi_arvalid,
    input  wire                       m_axi_arready,
    input  wire [AXI_ID_WIDTH-1:0]    m_axi_rid,
    input  wire [AXI_DATA_WIDTH-1:0]  m_axi_rdata,
    input  wire [1:0]                 m_axi_rresp,
    input  wire                       m_axi_rlast,
    input  wire                       m_axi_rvalid,
    output wire                       m_axi_rready,

    /*
     * Configuration
     */
    input  wire                       enable
);

parameter AXI_WORD_WIDTH = AXI_STRB_WIDTH;
parameter AXI_WORD_SIZE = AXI_DATA_WIDTH/AXI_WORD_WIDTH;
parameter AXI_BURST_SIZE = $clog2(AXI_STRB_WIDTH);
parameter AXI_MAX_BURST_SIZE = AXI_MAX_BURST_LEN << AXI_BURST_SIZE;

parameter AXIS_KEEP_WIDTH_INT = AXIS_KEEP_ENABLE ? AXIS_KEEP_WIDTH : 1;
parameter AXIS_WORD_WIDTH = AXIS_KEEP_WIDTH_INT;
parameter AXIS_WORD_SIZE = AXIS_DATA_WIDTH/AXIS_WORD_WIDTH;

parameter OFFSET_WIDTH = AXI_STRB_WIDTH > 1 ? $clog2(AXI_STRB_WIDTH) : 1;
parameter OFFSET_MASK = AXI_STRB_WIDTH > 1 ? {OFFSET_WIDTH{1'b1}} : 0;
parameter ADDR_MASK = {AXI_ADDR_WIDTH{1'b1}} << $clog2(AXI_STRB_WIDTH);
parameter CYCLE_COUNT_WIDTH = LEN_WIDTH - AXI_BURST_SIZE + 1;

// bus width assertions
initial begin
    if (AXI_WORD_SIZE * AXI_STRB_WIDTH != AXI_DATA_WIDTH) begin
        $error("Error: AXI data width not evenly divisble");
        $finish;
    end

    if (AXIS_WORD_SIZE * AXIS_KEEP_WIDTH_INT != AXIS_DATA_WIDTH) begin
        $error("Error: AXI stream data width not evenly divisble");
        $finish;
    end

    if (AXI_WORD_SIZE != AXIS_WORD_SIZE) begin
        $error("Error: word size mismatch");
        $finish;
    end

    if (2**$clog2(AXI_WORD_WIDTH) != AXI_WORD_WIDTH) begin
        $error("Error: AXI word width must be even power of two");
        $finish;
    end

    if (AXI_DATA_WIDTH != AXIS_DATA_WIDTH) begin
        $error("Error: AXI interface width must match AXI stream interface width");
        $finish;
    end

    if (AXI_MAX_BURST_LEN < 1 || AXI_MAX_BURST_LEN > 256) begin
        $error("Error: AXI_MAX_BURST_LEN must be between 1 and 256");
        $finish;
    end

    if (ENABLE_SG) begin
        $error("Error: scatter/gather is not yet implemented");
        $finish;
    end
end

localparam [0:0]
    AXI_STATE_IDLE = 1'd0,
    AXI_STATE_START = 1'd1;

reg [0:0] axi_state_reg = AXI_STATE_IDLE, axi_state_next;

localparam [0:0]
    AXIS_STATE_IDLE = 1'd0,
    AXIS_STATE_READ = 1'd1;

reg [0:0] axis_state_reg = AXIS_STATE_IDLE, axis_state_next;

// datapath control signals
reg transfer_in_save;
reg axis_cmd_ready;

reg [AXI_ADDR_WIDTH-1:0] addr_reg = {AXI_ADDR_WIDTH{1'b0}}, addr_next;
reg [LEN_WIDTH-1:0] op_word_count_reg = {LEN_WIDTH{1'b0}}, op_word_count_next;
reg [LEN_WIDTH-1:0] tr_word_count_reg = {LEN_WIDTH{1'b0}}, tr_word_count_next;

reg [OFFSET_WIDTH-1:0] axis_cmd_offset_reg = {OFFSET_WIDTH{1'b0}}, axis_cmd_offset_next;
reg [OFFSET_WIDTH-1:0] axis_cmd_last_cycle_offset_reg = {OFFSET_WIDTH{1'b0}}, axis_cmd_last_cycle_offset_next;
reg [CYCLE_COUNT_WIDTH-1:0] axis_cmd_input_cycle_count_reg = {CYCLE_COUNT_WIDTH{1'b0}}, axis_cmd_input_cycle_count_next;
reg [CYCLE_COUNT_WIDTH-1:0] axis_cmd_output_cycle_count_reg = {CYCLE_COUNT_WIDTH{1'b0}}, axis_cmd_output_cycle_count_next;
reg axis_cmd_bubble_cycle_reg = 1'b0, axis_cmd_bubble_cycle_next;
reg [TAG_WIDTH-1:0] axis_cmd_tag_reg = {TAG_WIDTH{1'b0}}, axis_cmd_tag_next;
reg [AXIS_ID_WIDTH-1:0] axis_cmd_axis_id_reg = {AXIS_ID_WIDTH{1'b0}}, axis_cmd_axis_id_next;
reg [AXIS_DEST_WIDTH-1:0] axis_cmd_axis_dest_reg = {AXIS_DEST_WIDTH{1'b0}}, axis_cmd_axis_dest_next;
reg [AXIS_USER_WIDTH-1:0] axis_cmd_axis_user_reg = {AXIS_USER_WIDTH{1'b0}}, axis_cmd_axis_user_next;
reg axis_cmd_valid_reg = 1'b0, axis_cmd_valid_next;

reg [OFFSET_WIDTH-1:0] offset_reg = {OFFSET_WIDTH{1'b0}}, offset_next;
reg [OFFSET_WIDTH-1:0] last_cycle_offset_reg = {OFFSET_WIDTH{1'b0}}, last_cycle_offset_next;
reg [CYCLE_COUNT_WIDTH-1:0] input_cycle_count_reg = {CYCLE_COUNT_WIDTH{1'b0}}, input_cycle_count_next;
reg [CYCLE_COUNT_WIDTH-1:0] output_cycle_count_reg = {CYCLE_COUNT_WIDTH{1'b0}}, output_cycle_count_next;
reg input_active_reg = 1'b0, input_active_next;
reg output_active_reg = 1'b0, output_active_next;
reg bubble_cycle_reg = 1'b0, bubble_cycle_next;
reg first_cycle_reg = 1'b0, first_cycle_next;
reg output_last_cycle_reg = 1'b0, output_last_cycle_next;

reg [TAG_WIDTH-1:0] tag_reg = {TAG_WIDTH{1'b0}}, tag_next;
reg [AXIS_ID_WIDTH-1:0] axis_id_reg = {AXIS_ID_WIDTH{1'b0}}, axis_id_next;
reg [AXIS_DEST_WIDTH-1:0] axis_dest_reg = {AXIS_DEST_WIDTH{1'b0}}, axis_dest_next;
reg [AXIS_USER_WIDTH-1:0] axis_user_reg = {AXIS_USER_WIDTH{1'b0}}, axis_user_next;

reg s_axis_read_desc_ready_reg = 1'b0, s_axis_read_desc_ready_next;

reg [TAG_WIDTH-1:0] m_axis_read_desc_status_tag_reg = {TAG_WIDTH{1'b0}}, m_axis_read_desc_status_tag_next;
reg m_axis_read_desc_status_valid_reg = 1'b0, m_axis_read_desc_status_valid_next;

reg [AXI_ADDR_WIDTH-1:0] m_axi_araddr_reg = {AXI_ADDR_WIDTH{1'b0}}, m_axi_araddr_next;
reg [7:0] m_axi_arlen_reg = 8'd0, m_axi_arlen_next;
reg m_axi_arvalid_reg = 1'b0, m_axi_arvalid_next;
reg m_axi_rready_reg = 1'b0, m_axi_rready_next;

reg [AXI_DATA_WIDTH-1:0] save_axi_rdata_reg = {AXI_DATA_WIDTH{1'b0}};

wire [AXI_DATA_WIDTH-1:0] shift_axi_rdata = {m_axi_rdata, save_axi_rdata_reg} >> ((AXI_STRB_WIDTH-offset_reg)*AXI_WORD_SIZE);

// internal datapath
reg  [AXIS_DATA_WIDTH-1:0] m_axis_read_data_tdata_int;
reg  [AXIS_KEEP_WIDTH-1:0] m_axis_read_data_tkeep_int;
reg                        m_axis_read_data_tvalid_int;
reg                        m_axis_read_data_tready_int_reg = 1'b0;
reg                        m_axis_read_data_tlast_int;
reg  [AXIS_ID_WIDTH-1:0]   m_axis_read_data_tid_int;
reg  [AXIS_DEST_WIDTH-1:0] m_axis_read_data_tdest_int;
reg  [AXIS_USER_WIDTH-1:0] m_axis_read_data_tuser_int;
wire                       m_axis_read_data_tready_int_early;

assign s_axis_read_desc_ready = s_axis_read_desc_ready_reg;

assign m_axis_read_desc_status_tag = m_axis_read_desc_status_tag_reg;
assign m_axis_read_desc_status_valid = m_axis_read_desc_status_valid_reg;

assign m_axi_arid = {AXI_ID_WIDTH{1'b0}};
assign m_axi_araddr = m_axi_araddr_reg;
assign m_axi_arlen = m_axi_arlen_reg;
assign m_axi_arsize = AXI_BURST_SIZE;
assign m_axi_arburst = 2'b01;
assign m_axi_arlock = 1'b0;
assign m_axi_arcache = 4'b0011;
assign m_axi_arprot = 3'b010;
assign m_axi_arvalid = m_axi_arvalid_reg;
assign m_axi_rready = m_axi_rready_reg;

wire [AXI_ADDR_WIDTH-1:0] addr_plus_max_burst = addr_reg + AXI_MAX_BURST_SIZE;
wire [AXI_ADDR_WIDTH-1:0] addr_plus_count = addr_reg + op_word_count_reg;

always @* begin
    axi_state_next = AXI_STATE_IDLE;

    s_axis_read_desc_ready_next = 1'b0;

    m_axi_araddr_next = m_axi_araddr_reg;
    m_axi_arlen_next = m_axi_arlen_reg;
    m_axi_arvalid_next = m_axi_arvalid_reg && !m_axi_arready;

    addr_next = addr_reg;
    op_word_count_next = op_word_count_reg;
    tr_word_count_next = tr_word_count_reg;

    axis_cmd_offset_next = axis_cmd_offset_reg;
    axis_cmd_last_cycle_offset_next = axis_cmd_last_cycle_offset_reg;
    axis_cmd_input_cycle_count_next = axis_cmd_input_cycle_count_reg;
    axis_cmd_output_cycle_count_next = axis_cmd_output_cycle_count_reg;
    axis_cmd_bubble_cycle_next = axis_cmd_bubble_cycle_reg;
    axis_cmd_tag_next = axis_cmd_tag_reg;
    axis_cmd_axis_id_next = axis_cmd_axis_id_reg;
    axis_cmd_axis_dest_next = axis_cmd_axis_dest_reg;
    axis_cmd_axis_user_next = axis_cmd_axis_user_reg;
    axis_cmd_valid_next = axis_cmd_valid_reg && !axis_cmd_ready;

    case (axi_state_reg)
        AXI_STATE_IDLE: begin
            // idle state - load new descriptor to start operation
            s_axis_read_desc_ready_next = !axis_cmd_valid_reg && enable;

            if (s_axis_read_desc_ready && s_axis_read_desc_valid) begin
                if (ENABLE_UNALIGNED) begin
                    addr_next = s_axis_read_desc_addr;
                    axis_cmd_offset_next = AXI_STRB_WIDTH > 1 ? AXI_STRB_WIDTH - (s_axis_read_desc_addr & OFFSET_MASK) : 0;
                    axis_cmd_bubble_cycle_next = axis_cmd_offset_next > 0;
                    axis_cmd_last_cycle_offset_next = s_axis_read_desc_len & OFFSET_MASK;
                end else begin
                    addr_next = s_axis_read_desc_addr & ADDR_MASK;
                    axis_cmd_offset_next = 0;
                    axis_cmd_bubble_cycle_next = 1'b0;
                    axis_cmd_last_cycle_offset_next = s_axis_read_desc_len & OFFSET_MASK;
                end
                axis_cmd_tag_next = s_axis_read_desc_tag;
                op_word_count_next = s_axis_read_desc_len;

                axis_cmd_axis_id_next = s_axis_read_desc_id;
                axis_cmd_axis_dest_next = s_axis_read_desc_dest;
                axis_cmd_axis_user_next = s_axis_read_desc_user;

                if (ENABLE_UNALIGNED) begin
                    axis_cmd_input_cycle_count_next = (op_word_count_next + (s_axis_read_desc_addr & OFFSET_MASK) - 1) >> AXI_BURST_SIZE;
                end else begin
                    axis_cmd_input_cycle_count_next = (op_word_count_next - 1) >> AXI_BURST_SIZE;
                end
                axis_cmd_output_cycle_count_next = (op_word_count_next - 1) >> AXI_BURST_SIZE;

                axis_cmd_valid_next = 1'b1;

                s_axis_read_desc_ready_next = 1'b0;
                axi_state_next = AXI_STATE_START;
            end else begin
                axi_state_next = AXI_STATE_IDLE;
            end
        end
        AXI_STATE_START: begin
            // start state - initiate new AXI transfer
            if (!m_axi_arvalid) begin
                if (op_word_count_reg <= AXI_MAX_BURST_SIZE - (addr_reg & OFFSET_MASK)) begin
                    // packet smaller than max burst size
                    if (addr_reg[12] != addr_plus_count[12]) begin
                        // crosses 4k boundary
                        tr_word_count_next = 13'h1000 - addr_reg[11:0];
                    end else begin
                        // does not cross 4k boundary
                        tr_word_count_next = op_word_count_reg;
                    end
                end else begin
                    // packet larger than max burst size
                    if (addr_reg[12] != addr_plus_max_burst[12]) begin
                        // crosses 4k boundary
                        tr_word_count_next = 13'h1000 - addr_reg[11:0];
                    end else begin
                        // does not cross 4k boundary
                        tr_word_count_next = AXI_MAX_BURST_SIZE - (addr_reg & OFFSET_MASK);
                    end
                end

                m_axi_araddr_next = addr_reg;
                if (ENABLE_UNALIGNED) begin
                    m_axi_arlen_next = (tr_word_count_next + (addr_reg & OFFSET_MASK) - 1) >> AXI_BURST_SIZE;
                end else begin
                    m_axi_arlen_next = (tr_word_count_next - 1) >> AXI_BURST_SIZE;
                end
                m_axi_arvalid_next = 1'b1;

                addr_next = addr_reg + tr_word_count_next;
                op_word_count_next = op_word_count_reg - tr_word_count_next;

                if (op_word_count_next > 0) begin
                    axi_state_next = AXI_STATE_START;
                end else begin
                    s_axis_read_desc_ready_next = !axis_cmd_valid_reg && enable;
                    axi_state_next = AXI_STATE_IDLE;
                end
            end else begin
                axi_state_next = AXI_STATE_START;
            end
        end
    endcase
end

always @* begin
    axis_state_next = AXIS_STATE_IDLE;

    m_axis_read_desc_status_tag_next = m_axis_read_desc_status_tag_reg;
    m_axis_read_desc_status_valid_next = 1'b0;

    m_axis_read_data_tdata_int = shift_axi_rdata;
    m_axis_read_data_tkeep_int = {AXIS_KEEP_WIDTH{1'b1}};
    m_axis_read_data_tlast_int = 1'b0;
    m_axis_read_data_tvalid_int = 1'b0;
    m_axis_read_data_tid_int = axis_id_reg;
    m_axis_read_data_tdest_int = axis_dest_reg;
    m_axis_read_data_tuser_int = axis_user_reg;

    m_axi_rready_next = 1'b0;

    transfer_in_save = 1'b0;
    axis_cmd_ready = 1'b0;

    offset_next = offset_reg;
    last_cycle_offset_next = last_cycle_offset_reg;
    input_cycle_count_next = input_cycle_count_reg;
    output_cycle_count_next = output_cycle_count_reg;
    input_active_next = input_active_reg;
    output_active_next = output_active_reg;
    bubble_cycle_next = bubble_cycle_reg;
    first_cycle_next = first_cycle_reg;
    output_last_cycle_next = output_last_cycle_reg;

    tag_next = tag_reg;
    axis_id_next = axis_id_reg;
    axis_dest_next = axis_dest_reg;
    axis_user_next = axis_user_reg;

    case (axis_state_reg)
        AXIS_STATE_IDLE: begin
            // idle state - load new descriptor to start operation
            m_axi_rready_next = 1'b0;

            // store transfer parameters
            if (ENABLE_UNALIGNED) begin
                offset_next = axis_cmd_offset_reg;
            end else begin
                offset_next = 0;
            end
            last_cycle_offset_next = axis_cmd_last_cycle_offset_reg;
            input_cycle_count_next = axis_cmd_input_cycle_count_reg;
            output_cycle_count_next = axis_cmd_output_cycle_count_reg;
            bubble_cycle_next = axis_cmd_bubble_cycle_reg;
            tag_next = axis_cmd_tag_reg;
            axis_id_next = axis_cmd_axis_id_reg;
            axis_dest_next = axis_cmd_axis_dest_reg;
            axis_user_next = axis_cmd_axis_user_reg;

            output_last_cycle_next = output_cycle_count_next == 0;
            input_active_next = 1'b1;
            output_active_next = 1'b1;
            first_cycle_next = 1'b1;

            if (axis_cmd_valid_reg) begin
                axis_cmd_ready = 1'b1;
                m_axi_rready_next = m_axis_read_data_tready_int_early;
                axis_state_next = AXIS_STATE_READ;
            end
        end
        AXIS_STATE_READ: begin
            // handle AXI read data
            m_axi_rready_next = m_axis_read_data_tready_int_early && input_active_reg;

            if (m_axis_read_data_tready_int_reg && ((m_axi_rready && m_axi_rvalid) || !input_active_reg)) begin
                // transfer in AXI read data
                transfer_in_save = m_axi_rready && m_axi_rvalid;

                if (ENABLE_UNALIGNED && first_cycle_reg && bubble_cycle_reg) begin
                    if (input_active_reg) begin
                        input_cycle_count_next = input_cycle_count_reg - 1;
                        input_active_next = input_cycle_count_reg > 0;
                    end
                    bubble_cycle_next = 1'b0;
                    first_cycle_next = 1'b0;

                    m_axi_rready_next = m_axis_read_data_tready_int_early && input_active_next;
                    axis_state_next = AXIS_STATE_READ;
                end else begin
                    // update counters
                    if (input_active_reg) begin
                        input_cycle_count_next = input_cycle_count_reg - 1;
                        input_active_next = input_cycle_count_reg > 0;
                    end
                    if (output_active_reg) begin
                        output_cycle_count_next = output_cycle_count_reg - 1;
                        output_active_next = output_cycle_count_reg > 0;
                    end
                    output_last_cycle_next = output_cycle_count_next == 0;
                    bubble_cycle_next = 1'b0;
                    first_cycle_next = 1'b0;

                    // pass through read data
                    m_axis_read_data_tdata_int = shift_axi_rdata;
                    m_axis_read_data_tkeep_int = {AXIS_KEEP_WIDTH_INT{1'b1}};
                    m_axis_read_data_tvalid_int = 1'b1;

                    if (output_last_cycle_reg) begin
                        // no more data to transfer, finish operation
                        if (last_cycle_offset_reg > 0) begin
                            m_axis_read_data_tkeep_int = {AXIS_KEEP_WIDTH_INT{1'b1}} >> (AXIS_KEEP_WIDTH_INT - last_cycle_offset_reg);
                        end
                        m_axis_read_data_tlast_int = 1'b1;

                        m_axis_read_desc_status_tag_next = tag_reg;
                        m_axis_read_desc_status_valid_next = 1'b1;

                        m_axi_rready_next = 1'b0;
                        axis_state_next = AXIS_STATE_IDLE;
                    end else begin
                        // more cycles in AXI transfer
                        m_axi_rready_next = m_axis_read_data_tready_int_early && input_active_next;
                        axis_state_next = AXIS_STATE_READ;
                    end
                end
            end else begin
                axis_state_next = AXIS_STATE_READ;
            end
        end
    endcase
end

always @(posedge clk) begin
    if (rst) begin
        axi_state_reg <= AXI_STATE_IDLE;
        axis_state_reg <= AXIS_STATE_IDLE;
        axis_cmd_valid_reg <= 1'b0;
        s_axis_read_desc_ready_reg <= 1'b0;
        m_axis_read_desc_status_valid_reg <= 1'b0;
        m_axi_arvalid_reg <= 1'b0;
        m_axi_rready_reg <= 1'b0;
    end else begin
        axi_state_reg <= axi_state_next;
        axis_state_reg <= axis_state_next;
        axis_cmd_valid_reg <= axis_cmd_valid_next;
        s_axis_read_desc_ready_reg <= s_axis_read_desc_ready_next;
        m_axis_read_desc_status_valid_reg <= m_axis_read_desc_status_valid_next;
        m_axi_arvalid_reg <= m_axi_arvalid_next;
        m_axi_rready_reg <= m_axi_rready_next;
    end

    m_axis_read_desc_status_tag_reg <= m_axis_read_desc_status_tag_next;

    m_axi_araddr_reg <= m_axi_araddr_next;
    m_axi_arlen_reg <= m_axi_arlen_next;

    addr_reg <= addr_next;
    op_word_count_reg <= op_word_count_next;
    tr_word_count_reg <= tr_word_count_next;

    axis_cmd_offset_reg <= axis_cmd_offset_next;
    axis_cmd_last_cycle_offset_reg <= axis_cmd_last_cycle_offset_next;
    axis_cmd_input_cycle_count_reg <= axis_cmd_input_cycle_count_next;
    axis_cmd_output_cycle_count_reg <= axis_cmd_output_cycle_count_next;
    axis_cmd_bubble_cycle_reg <= axis_cmd_bubble_cycle_next;
    axis_cmd_tag_reg <= axis_cmd_tag_next;
    axis_cmd_axis_id_reg <= axis_cmd_axis_id_next;
    axis_cmd_axis_dest_reg <= axis_cmd_axis_dest_next;
    axis_cmd_axis_user_reg <= axis_cmd_axis_user_next;
    axis_cmd_valid_reg <= axis_cmd_valid_next;

    offset_reg <= offset_next;
    last_cycle_offset_reg <= last_cycle_offset_next;
    input_cycle_count_reg <= input_cycle_count_next;
    output_cycle_count_reg <= output_cycle_count_next;
    input_active_reg <= input_active_next;
    output_active_reg <= output_active_next;
    bubble_cycle_reg <= bubble_cycle_next;
    first_cycle_reg <= first_cycle_next;
    output_last_cycle_reg <= output_last_cycle_next;

    tag_reg <= tag_next;
    axis_id_reg <= axis_id_next;
    axis_dest_reg <= axis_dest_next;
    axis_user_reg <= axis_user_next;

    if (transfer_in_save) begin
        save_axi_rdata_reg <= m_axi_rdata;
    end
end

// output datapath logic
reg [AXIS_DATA_WIDTH-1:0] m_axis_read_data_tdata_reg  = {AXIS_DATA_WIDTH{1'b0}};
reg [AXIS_KEEP_WIDTH-1:0] m_axis_read_data_tkeep_reg  = {AXIS_KEEP_WIDTH{1'b0}};
reg                       m_axis_read_data_tvalid_reg = 1'b0, m_axis_read_data_tvalid_next;
reg                       m_axis_read_data_tlast_reg  = 1'b0;
reg [AXIS_ID_WIDTH-1:0]   m_axis_read_data_tid_reg    = {AXIS_ID_WIDTH{1'b0}};
reg [AXIS_DEST_WIDTH-1:0] m_axis_read_data_tdest_reg  = {AXIS_DEST_WIDTH{1'b0}};
reg [AXIS_USER_WIDTH-1:0] m_axis_read_data_tuser_reg  = {AXIS_USER_WIDTH{1'b0}};

reg [AXIS_DATA_WIDTH-1:0] temp_m_axis_read_data_tdata_reg  = {AXIS_DATA_WIDTH{1'b0}};
reg [AXIS_KEEP_WIDTH-1:0] temp_m_axis_read_data_tkeep_reg  = {AXIS_KEEP_WIDTH{1'b0}};
reg                       temp_m_axis_read_data_tvalid_reg = 1'b0, temp_m_axis_read_data_tvalid_next;
reg                       temp_m_axis_read_data_tlast_reg  = 1'b0;
reg [AXIS_ID_WIDTH-1:0]   temp_m_axis_read_data_tid_reg    = {AXIS_ID_WIDTH{1'b0}};
reg [AXIS_DEST_WIDTH-1:0] temp_m_axis_read_data_tdest_reg  = {AXIS_DEST_WIDTH{1'b0}};
reg [AXIS_USER_WIDTH-1:0] temp_m_axis_read_data_tuser_reg  = {AXIS_USER_WIDTH{1'b0}};

// datapath control
reg store_axis_int_to_output;
reg store_axis_int_to_temp;
reg store_axis_temp_to_output;

assign m_axis_read_data_tdata  = m_axis_read_data_tdata_reg;
assign m_axis_read_data_tkeep  = AXIS_KEEP_ENABLE ? m_axis_read_data_tkeep_reg : {AXIS_KEEP_WIDTH{1'b1}};
assign m_axis_read_data_tvalid = m_axis_read_data_tvalid_reg;
assign m_axis_read_data_tlast  = AXIS_LAST_ENABLE ? m_axis_read_data_tlast_reg : 1'b1;
assign m_axis_read_data_tid    = AXIS_ID_ENABLE   ? m_axis_read_data_tid_reg   : {AXIS_ID_WIDTH{1'b0}};
assign m_axis_read_data_tdest  = AXIS_DEST_ENABLE ? m_axis_read_data_tdest_reg : {AXIS_DEST_WIDTH{1'b0}};
assign m_axis_read_data_tuser  = AXIS_USER_ENABLE ? m_axis_read_data_tuser_reg : {AXIS_USER_WIDTH{1'b0}};

// enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)
assign m_axis_read_data_tready_int_early = m_axis_read_data_tready || (!temp_m_axis_read_data_tvalid_reg && (!m_axis_read_data_tvalid_reg || !m_axis_read_data_tvalid_int));

always @* begin
    // transfer sink ready state to source
    m_axis_read_data_tvalid_next = m_axis_read_data_tvalid_reg;
    temp_m_axis_read_data_tvalid_next = temp_m_axis_read_data_tvalid_reg;

    store_axis_int_to_output = 1'b0;
    store_axis_int_to_temp = 1'b0;
    store_axis_temp_to_output = 1'b0;

    if (m_axis_read_data_tready_int_reg) begin
        // input is ready
        if (m_axis_read_data_tready || !m_axis_read_data_tvalid_reg) begin
            // output is ready or currently not valid, transfer data to output
            m_axis_read_data_tvalid_next = m_axis_read_data_tvalid_int;
            store_axis_int_to_output = 1'b1;
        end else begin
            // output is not ready, store input in temp
            temp_m_axis_read_data_tvalid_next = m_axis_read_data_tvalid_int;
            store_axis_int_to_temp = 1'b1;
        end
    end else if (m_axis_read_data_tready) begin
        // input is not ready, but output is ready
        m_axis_read_data_tvalid_next = temp_m_axis_read_data_tvalid_reg;
        temp_m_axis_read_data_tvalid_next = 1'b0;
        store_axis_temp_to_output = 1'b1;
    end
end

always @(posedge clk) begin
    if (rst) begin
        m_axis_read_data_tvalid_reg <= 1'b0;
        m_axis_read_data_tready_int_reg <= 1'b0;
        temp_m_axis_read_data_tvalid_reg <= 1'b0;
    end else begin
        m_axis_read_data_tvalid_reg <= m_axis_read_data_tvalid_next;
        m_axis_read_data_tready_int_reg <= m_axis_read_data_tready_int_early;
        temp_m_axis_read_data_tvalid_reg <= temp_m_axis_read_data_tvalid_next;
    end

    // datapath
    if (store_axis_int_to_output) begin
        m_axis_read_data_tdata_reg <= m_axis_read_data_tdata_int;
        m_axis_read_data_tkeep_reg <= m_axis_read_data_tkeep_int;
        m_axis_read_data_tlast_reg <= m_axis_read_data_tlast_int;
        m_axis_read_data_tid_reg   <= m_axis_read_data_tid_int;
        m_axis_read_data_tdest_reg <= m_axis_read_data_tdest_int;
        m_axis_read_data_tuser_reg <= m_axis_read_data_tuser_int;
    end else if (store_axis_temp_to_output) begin
        m_axis_read_data_tdata_reg <= temp_m_axis_read_data_tdata_reg;
        m_axis_read_data_tkeep_reg <= temp_m_axis_read_data_tkeep_reg;
        m_axis_read_data_tlast_reg <= temp_m_axis_read_data_tlast_reg;
        m_axis_read_data_tid_reg   <= temp_m_axis_read_data_tid_reg;
        m_axis_read_data_tdest_reg <= temp_m_axis_read_data_tdest_reg;
        m_axis_read_data_tuser_reg <= temp_m_axis_read_data_tuser_reg;
    end

    if (store_axis_int_to_temp) begin
        temp_m_axis_read_data_tdata_reg <= m_axis_read_data_tdata_int;
        temp_m_axis_read_data_tkeep_reg <= m_axis_read_data_tkeep_int;
        temp_m_axis_read_data_tlast_reg <= m_axis_read_data_tlast_int;
        temp_m_axis_read_data_tid_reg   <= m_axis_read_data_tid_int;
        temp_m_axis_read_data_tdest_reg <= m_axis_read_data_tdest_int;
        temp_m_axis_read_data_tuser_reg <= m_axis_read_data_tuser_int;
    end
end

endmodule
