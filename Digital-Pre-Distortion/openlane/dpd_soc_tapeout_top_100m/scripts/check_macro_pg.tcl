if {![info exists ::env(RUN_TAG)]} {
    puts stderr "RUN_TAG is required"
    exit 2
}

set odb_file "/openlane/designs/dpd_soc_tapeout_top_100m/runs/$::env(RUN_TAG)/results/floorplan/dpd_soc_tapeout_top.odb"
read_db $odb_file
set db [ord::get_db]
set chip [$db getChip]
set block [$chip getBlock]
set failures 0

foreach name {u_axi u_capture_ram u_coef_bank u_gmp u_mac u_metrics u_peripherals u_pico} {
    set inst [$block findInst $name]
    if {$inst == "NULL"} {
        puts "FAIL $name missing"
        incr failures
        continue
    }
    set vpwr [[$inst findITerm VPWR] getNet]
    set vgnd [[$inst findITerm VGND] getNet]
    set vpwr_name [expr {$vpwr == "NULL" ? "UNCONNECTED" : [$vpwr getName]}]
    set vgnd_name [expr {$vgnd == "NULL" ? "UNCONNECTED" : [$vgnd getName]}]
    puts "$name VPWR=$vpwr_name VGND=$vgnd_name"
    if {$vpwr_name ne "VPWR" || $vgnd_name ne "VGND"} {
        incr failures
    }
}

if {$failures != 0} {
    puts stderr "FAIL macro PG connections: $failures"
    exit 1
}
puts "PASS all macro PG instance terminals use VPWR/VGND"
exit
