#!/usr/bin/env python3
# -*- coding: utf-8 -*-

#
# SPDX-License-Identifier: GPL-3.0
#
# GNU Radio Python Flow Graph
# Title: ATSC 3.0 A/322 8K 256QAM 6 MHz 24 Msps Baseband Dataset
# Author: drmpeg
# GNU Radio version: 3.10.12.0

from gnuradio import blocks
import pmt
from gnuradio import digital
from gnuradio import filter
from gnuradio.filter import firdes
from gnuradio import gr
from gnuradio.fft import window
import sys
import signal
from argparse import ArgumentParser
from gnuradio.eng_arg import eng_float, intx
from gnuradio import eng_notation
import atsc3
import threading




class atsc3_a322_vv031_8k_256qam_fs24m_baseband(gr.top_block):

    def __init__(self):
        gr.top_block.__init__(self, "ATSC 3.0 A/322 8K 256QAM 6 MHz 24 Msps Baseband Dataset", catch_exceptions=True)
        self.flowgraph_started = threading.Event()

        ##################################################
        # Variables
        ##################################################
        self.samp_rate = samp_rate = 384000 * (16 + 2)
        self.center_freq = center_freq = 429e6

        ##################################################
        # Blocks
        ##################################################

        self.rational_resampler_xxx_0 = filter.rational_resampler_ccf(
                interpolation=125,
                decimation=36,
                taps=[],
                fractional_bw=0.40)
        self.digital_ofdm_cyclic_prefixer_0 = digital.ofdm_cyclic_prefixer(
            8192,
            8192 + 1024,
            0,
            '')
        self.blocks_head_0 = blocks.head(gr.sizeof_gr_complex*1, 262144)
        self.blocks_file_source_0 = blocks.file_source(gr.sizeof_char*1, '/home/Ausilon/miniconda3/datasets/sample_1280x720.ts', False, 0, 0)
        self.blocks_file_source_0.set_begin_tag(pmt.PMT_NIL)
        self.blocks_file_sink_0 = blocks.file_sink(gr.sizeof_gr_complex*1, '/home/Ausilon/Desktop/dpd_v1/dpd_soc_min/datasets/atsc3_a322_vv031_8k_256qam_fs24m/atsc3_a322_vv031_8k_256qam_baseband_fs24m_complex64.bin', False)
        self.blocks_file_sink_0.set_unbuffered(False)
        self.atsc3_pilotgenerator_cc_0 = atsc3.pilotgenerator_cc(
            atsc3.FFTSIZE_8K,
            72,
            2,
            atsc3.GI_5_1024,
            atsc3.PILOT_SP3_4,
            atsc3.SPB_4,
            atsc3.SBS_OFF,
            atsc3.CRED_0,
            atsc3.MISO_OFF,
            atsc3.MISO_TX_1_OF_2,
            atsc3.PAPR_OFF,
            atsc3.PILOTGENERATOR_TIME,
            8192,
            8192)
        self.atsc3_modulator_bc_0 = atsc3.modulator_bc(
            atsc3.FECFRAME_NORMAL,
            atsc3.C9_15,
            atsc3.MOD_256QAM
            )
        self.atsc3_ldpc_bb_0 = atsc3.ldpc_bb(atsc3.FECFRAME_NORMAL, atsc3.C9_15)
        self.atsc3_interleaver_bb_0 = atsc3.interleaver_bb(
            atsc3.FECFRAME_NORMAL,
            atsc3.C9_15,
            atsc3.MOD_256QAM
            )
        self.atsc3_freqinterleaver_cc_0 = atsc3.freqinterleaver_cc(
            atsc3.FFTSIZE_8K,
            72,
            2,
            atsc3.GI_5_1024,
            atsc3.PILOT_SP3_4,
            atsc3.SBS_OFF,
            atsc3.FREQ_PREAMBLE_ONLY,
            atsc3.CRED_0,
            atsc3.PAPR_OFF)
        self.atsc3_framemapper_cc_0 = atsc3.framemapper_cc(
            atsc3.FECFRAME_NORMAL,
            atsc3.C9_15,
            atsc3.PLP_FEC_BCH,
            atsc3.MOD_256QAM,
            atsc3.FFTSIZE_8K,
            72,
            2,
            atsc3.GI_5_1024,
            atsc3.PILOT_SP3_4,
            atsc3.SPB_4,
            atsc3.SBS_OFF,
            atsc3.FREQ_PREAMBLE_ONLY,
            atsc3.TI_MODE_OFF,
            atsc3.TI_DEPTH_1024,
            2,
            14,
            14,
            0,
            atsc3.LLS_OFF,
            atsc3.CRED_0,
            atsc3.FLM_SYMBOL_ALIGNED,
            100,
            atsc3.TIF_NOT_INCLUDED,
            atsc3.MISO_OFF,
            atsc3.PAPR_OFF,
            atsc3.L1_FEC_MODE_1,
            atsc3.L1_FEC_MODE_1)
        self.atsc3_bootstrap_cc_0 = atsc3.bootstrap_cc(
            atsc3.FFTSIZE_8K,
            72,
            2,
            atsc3.GI_5_1024,
            atsc3.PILOT_SP3_4,
            atsc3.MTTN_100,
            atsc3.FLM_SYMBOL_ALIGNED,
            100,
            atsc3.L1_FEC_MODE_1,
            atsc3.BOOTSTRAP_MAJOR_VERSION_0,
            atsc3.BOOTSTRAP_MINOR_VERSION_0,
            atsc3.BOOTSTRAP_INTERPOLATION,
            atsc3.SHOWLEVELS_OFF,
            3.3)
        self.atsc3_bch_bb_0 = atsc3.bch_bb(atsc3.FECFRAME_NORMAL, atsc3.C9_15, atsc3.PLP_FEC_BCH)
        self.atsc3_bbscrambler_bb_0 = atsc3.bbscrambler_bb(atsc3.FECFRAME_NORMAL, atsc3.C9_15, atsc3.PLP_FEC_BCH)
        self.atsc3_alpbbheader_bb_0 = atsc3.alpbbheader_bb(atsc3.FECFRAME_NORMAL, atsc3.C9_15, atsc3.LLS_OFF, atsc3.LLS_ONE_SERVICE)


        ##################################################
        # Connections
        ##################################################
        self.connect((self.atsc3_alpbbheader_bb_0, 0), (self.atsc3_bbscrambler_bb_0, 0))
        self.connect((self.atsc3_bbscrambler_bb_0, 0), (self.atsc3_bch_bb_0, 0))
        self.connect((self.atsc3_bch_bb_0, 0), (self.atsc3_ldpc_bb_0, 0))
        self.connect((self.atsc3_bootstrap_cc_0, 0), (self.rational_resampler_xxx_0, 0))
        self.connect((self.atsc3_framemapper_cc_0, 0), (self.atsc3_freqinterleaver_cc_0, 0))
        self.connect((self.atsc3_freqinterleaver_cc_0, 0), (self.atsc3_pilotgenerator_cc_0, 0))
        self.connect((self.atsc3_interleaver_bb_0, 0), (self.atsc3_modulator_bc_0, 0))
        self.connect((self.atsc3_ldpc_bb_0, 0), (self.atsc3_interleaver_bb_0, 0))
        self.connect((self.atsc3_modulator_bc_0, 0), (self.atsc3_framemapper_cc_0, 0))
        self.connect((self.atsc3_pilotgenerator_cc_0, 0), (self.digital_ofdm_cyclic_prefixer_0, 0))
        self.connect((self.blocks_file_source_0, 0), (self.atsc3_alpbbheader_bb_0, 0))
        self.connect((self.blocks_head_0, 0), (self.blocks_file_sink_0, 0))
        self.connect((self.digital_ofdm_cyclic_prefixer_0, 0), (self.atsc3_bootstrap_cc_0, 0))
        self.connect((self.rational_resampler_xxx_0, 0), (self.blocks_head_0, 0))


    def get_samp_rate(self):
        return self.samp_rate

    def set_samp_rate(self, samp_rate):
        self.samp_rate = samp_rate

    def get_center_freq(self):
        return self.center_freq

    def set_center_freq(self, center_freq):
        self.center_freq = center_freq




def main(top_block_cls=atsc3_a322_vv031_8k_256qam_fs24m_baseband, options=None):
    tb = top_block_cls()

    def sig_handler(sig=None, frame=None):
        tb.stop()
        tb.wait()

        sys.exit(0)

    signal.signal(signal.SIGINT, sig_handler)
    signal.signal(signal.SIGTERM, sig_handler)

    tb.start()
    tb.flowgraph_started.set()

    tb.wait()


if __name__ == '__main__':
    main()
