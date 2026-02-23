//
//  FreeDV.swift
//  Codec2
//
//  Created by Brandon Wiley on 7/23/17.
//

import Foundation

public enum Mode: Int32 {
    /// 1500 bps
    case _1500  = 0
    /// 700 bps
    case _700 = 1
    /// 700 bps (improved)
    case _700b = 2
    /// 2400 bps
    case _2400A = 3
    /// 2400 bps
    case _2400B = 4
    /// 800 bps
    case _800XA = 5
    /// 700 bps
    case _700C = 6
}

public class FreeDV {
    var instance: OpaquePointer

    init?(_ mode: Mode) {
        let maybeFreedvPtr = freedv_open(mode.rawValue)
        guard let freedvPtr = maybeFreedvPtr else {
            return nil
        }
        
        instance = freedvPtr
        squelch_en = 1
        snr_squelch_thresh = -100
    }
    
    func close() {
        freedv_close(instance)
    }
    
    func transmit(in speechStream: InputStream, out modStream: OutputStream) {
        // n_speech_samples and n_nom_modem_samples counts Int16, but streams require UInt8s
        let byteSpeechSamples = self.n_speech_samples * 2
        let byteModemSamples = self.n_nom_modem_samples * 2

        let speechBuff8 = UnsafeMutablePointer<UInt8>.allocate(capacity: byteSpeechSamples)
        let modBuff16 = UnsafeMutablePointer<Int16>.allocate(capacity: self.n_nom_modem_samples)
        
        _ = speechBuff8.withMemoryRebound(to: Int16.self, capacity: self.n_speech_samples) {
            (speechBuff16) in
            
            while(speechStream.read(speechBuff8, maxLength: byteSpeechSamples) == byteSpeechSamples)
            {
                txUnsafe(modBuff16, speechBuff16)

                _ = modBuff16.withMemoryRebound(to: UInt8.self, capacity: byteModemSamples) {
                    (modBuff8) in
                    
                    modStream.write(modBuff8, maxLength: byteModemSamples)
                }
            }
        }
    }

    func receive(in demodStream: InputStream, out speechStream: OutputStream) {
        // n_speech_samples and n_nom_modem_samples counts Int16, but streams require UInt8s
        let byteSpeechSamples = self.n_speech_samples * 2
        let byteModemSamples = self.n_nom_modem_samples * 2
        
        let demodBuff8 = UnsafeMutablePointer<UInt8>.allocate(capacity: byteModemSamples)
        let speechBuff16 = UnsafeMutablePointer<Int16>.allocate(capacity: self.n_speech_samples)
        
        _ = demodBuff8.withMemoryRebound(to: Int16.self, capacity: self.n_nom_modem_samples) {
            (demodBuff16) in
            
            var byteNinSamples = nin * 2
            
            while(demodStream.read(demodBuff8, maxLength: byteNinSamples) == byteNinSamples)
            {
                let noutSamples = rxUnsafe(speechBuff16, demodBuff16)
                let byteNoutSamples = noutSamples * 2
                
                _ = speechBuff16.withMemoryRebound(to: UInt8.self, capacity: byteSpeechSamples) {
                    (speechBuff8) in

                    speechStream.write(speechBuff8, maxLength: byteNoutSamples)
                }
                
                byteNinSamples = nin * 2
            }
        }
    }
    
    //# MARK: Parameters
    var squelch_en: Int {
        willSet {
            freedv_set_squelch_en(instance, Int32(newValue))
        }
    }
    var snr_squelch_thresh: Float {
        willSet {
            freedv_set_snr_squelch_thresh(instance, newValue)
        }
    }
    
    var n_speech_samples: Int {
        get {
            return Int(freedv_get_n_speech_samples(instance));
        }
    }
    
    var n_nom_modem_samples: Int {
        get {
            return Int(freedv_get_n_nom_modem_samples(instance));
        }
    }
    
    var n_max_modem_samples: Int {
        get {
            return Int(freedv_get_n_max_modem_samples(instance));
        }
    }

    var modem_sample_rate: Int {
        get {
            return Int(freedv_get_modem_sample_rate(instance));
        }
    }
    
    var nin: Int {
        get {
            return Int(freedv_nin(instance))
        }
    }
    
    var total_bits: Int {
        get {
            return Int(freedv_get_total_bits(instance))
        }
        
        set {
            freedv_set_total_bits(instance, Int32(newValue))
        }
    }

    var total_bit_errors: Int {
        get {
            return Int(freedv_get_total_bit_errors(instance))
        }
        
        set {
            freedv_set_total_bit_errors(instance, Int32(newValue))
        }
    }

    var protocol_bits: Int {
        get {
            return Int(freedv_get_protocol_bits(instance))
        }
    }
    
    var sz_error_pattern: Int {
        get {
            return Int(freedv_get_sz_error_pattern(instance))
        }
    }

    var n_codec_bits: Int {
        get {
            return Int(freedv_get_n_codec_bits(instance))
        }
    }

    var test_frames: Int {
        get {
            return Int(freedv_get_test_frames(instance))
        }
    }
    
    var sync: Int {
        get {
            return Int(freedv_get_sync(instance))
        }
    }

    var version: Int {
        get {
            return Int(freedv_get_version())
        }
    }
    
    var mode: Mode {
        get {
            return Mode(rawValue: freedv_get_mode(instance))!
        }
    }
    
    var clip: Int? {
        willSet {
            if let clipValue = newValue
            {
                freedv_set_clip(instance, Int32(clipValue))
            }
        }
    }
    
    var varicode_code_num: Int? {
        willSet {
            if let codeValue = newValue {
                freedv_set_varicode_code_num(instance, Int32(codeValue))
            }
        }
    }
    
    var data_header: Data? {
        willSet {
            if let dataValue = newValue {
                var mutData = dataValue
                mutData.withUnsafeMutableBytes {(dataPtr: UnsafeMutablePointer<UInt8>)->Void in
                    freedv_set_data_header(instance, dataPtr)
                }
            }
        }
    }
    
    //# MARK: Transmit
    
    func tx(_ mod_out: inout [Int16], _ speech_in: [Int16]) {
        let modPtr = UnsafeMutablePointer(mutating: mod_out)
        let speechPtr = UnsafeMutablePointer(mutating: speech_in)
        freedv_tx(instance, modPtr, speechPtr)
    }
    
    func txUnsafe(_ modPtr: UnsafeMutablePointer<Int16>, _ speechPtr: UnsafeMutablePointer<Int16>)
    {
        freedv_tx(instance, modPtr, speechPtr)
    }
    
    // void freedv_comptx  (struct freedv *freedv, COMP  mod_out[], short speech_in[]);
    // void freedv_codectx (struct freedv *f, short mod_out[], unsigned char *packed_codec_bits);
    // void freedv_datatx  (struct freedv *f, short mod_out[]);
    // int  freedv_data_ntxframes (struct freedv *freedv);

    //# MARK: Receive
    
    func rx(_ speech_out: inout [Int16], _ demod_in: [Int16]) -> Int {
        let speechPtr = UnsafeMutablePointer(mutating: speech_out)
        let demodPtr = UnsafeMutablePointer(mutating: demod_in)
        return Int(freedv_rx(instance, speechPtr, demodPtr))
    }

    func rxUnsafe(_ speechPtr: UnsafeMutablePointer<Int16>, _ demodPtr: UnsafeMutablePointer<Int16>) -> Int
    {
        return Int(freedv_rx(instance, speechPtr, demodPtr))
    }
    
    // int freedv_floatrx  (struct freedv *freedv, short speech_out[], float demod_in[]);
    // int freedv_comprx   (struct freedv *freedv, short speech_out[], COMP  demod_in[]);
    // int freedv_codecrx  (struct freedv *freedv, unsigned char *packed_codec_bits, short demod_in[]);
    
    //# MARK: Set parameters
     
    // void freedv_set_callback_txt            (struct freedv *freedv, freedv_callback_rx rx, freedv_callback_tx tx, void *callback_state);
    // void freedv_set_callback_protocol       (struct freedv *freedv, freedv_callback_protorx rx, freedv_callback_prototx tx, void *callback_state);
    // void freedv_set_callback_data         (struct freedv *freedv, freedv_callback_datarx datarx, freedv_callback_datatx datatx, void *callback_state);
    // void freedv_set_test_frames			    (struct freedv *freedv, int test_frames);
    // void freedv_set_smooth_symbols		    (struct freedv *freedv, int smooth_symbols);
    
    /*
     void freedv_set_callback_error_pattern  (struct freedv *freedv, freedv_calback_error_pattern cb, void *state);
     
     //# MARK: Get parameters
     
     struct MODEM_STATS;
     void freedv_get_modem_stats         (struct freedv *freedv, int *sync, float *snr_est);
     void freedv_get_modem_extended_stats(struct freedv *freedv, struct MODEM_STATS *stats);
     struct CODEC2 *freedv_get_codec2	(struct freedv *freedv);
     
     //# MARK: Callbacks
     
     typedef void (*freedv_callback_rx)(void *, char);
     typedef char (*freedv_callback_tx)(void *);
     typedef void (*freedv_calback_error_pattern)
     (void *error_pattern_callback_state, short error_pattern[], int sz_error_pattern);
     
     typedef void (*freedv_callback_protorx)(void *, char *);
     typedef void (*freedv_callback_prototx)(void *, char *);
     
     typedef void (*freedv_callback_datarx)(void *, unsigned char *packet, size_t size);
     typedef void (*freedv_callback_datatx)(void *, unsigned char *packet, size_t *size);
     */
}

