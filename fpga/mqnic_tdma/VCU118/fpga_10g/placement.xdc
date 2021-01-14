# Placement constraints
#create_pblock pblock_slr0
#add_cells_to_pblock [get_pblocks pblock_slr0] [get_cells -quiet [list ]]
#resize_pblock [get_pblocks pblock_slr0] -add {SLR0}

create_pblock pblock_slr1
add_cells_to_pblock [get_pblocks pblock_slr1] [get_cells -quiet [list pcie4_uscale_plus_inst]]
add_cells_to_pblock [get_pblocks pblock_slr1] [get_cells -quiet [list core_inst/dma_if_pcie_us_inst]]
add_cells_to_pblock [get_pblocks pblock_slr1] [get_cells -quiet [list core_inst/dma_if_mux_inst]]
resize_pblock [get_pblocks pblock_slr1] -add {SLR1}

#create_pblock pblock_slr2
#add_cells_to_pblock [get_pblocks pblock_slr2] [get_cells -quiet [list ]]
#resize_pblock [get_pblocks pblock_slr2] -add {SLR2}
