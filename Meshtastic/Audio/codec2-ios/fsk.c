/*---------------------------------------------------------------------------*\

  FILE........: fsk.c
  AUTHOR......: Brady O'Brien
  DATE CREATED: 7 January 2016

  C Implementation of 2/4FSK modulator/demodulator, based on octave/fsk_horus.m

\*---------------------------------------------------------------------------*/

/*
  Copyright (C) 2016 David Rowe

  All rights reserved.

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU Lesser General Public License version 2.1, as
  published by the Free Software Foundation.  This program is
  distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
  License for more details.

  You should have received a copy of the GNU Lesser General Public License
  along with this program; if not, see <http://www.gnu.org/licenses/>.
*/

/*---------------------------------------------------------------------------*\

                               DEFINES

\*---------------------------------------------------------------------------*/

/* P oversampling rate constant -- should probably be init-time configurable */
#define horus_P 8

/* Define this to enable EbNodB estimate */
/* This needs square roots, may take more cpu time than it's worth */
#define EST_EBNO

/* This is a flag to make the mod/demod allocate their memory on the stack instead of the heap */
/* At large sample rates, there's not enough stack space to run the demod */
#define DEMOD_ALLOC_STACK
/*---------------------------------------------------------------------------*\

                               INCLUDES

\*---------------------------------------------------------------------------*/

#include <assert.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>

#include "fsk.h"
#include "comp_prim.h"
#include "kiss_fftr.h"
#include "modem_probe.h"

/*---------------------------------------------------------------------------*\

                               FUNCTIONS

\*---------------------------------------------------------------------------*/

/*
 * Euler's formula in a new convenient function
 */
static inline COMP comp_exp_j(float phi){
    COMP res;
    res.real = cosf(phi);
    res.imag = sinf(phi);
    return res;
}

/*
 * Quick and easy complex 0
 */
static inline COMP comp0(){
    COMP res;
    res.real = 0;
    res.imag = 0;
    return res;
}

/*
 * Quick and easy complex subtract
 */
static inline COMP csub(COMP a, COMP b){
    COMP res;
    res.real = a.real-b.real;
    res.imag = a.imag-b.imag;
    return res;
}

/*
 * Compare the magnitude of a and b. if |a|>|b|, return true, otw false.
 * This needs no square roots
 */
static inline int comp_mag_gt(COMP a,COMP b){
    return ((a.real*a.real)+(a.imag*a.imag)) > ((b.real*b.real)+(b.imag*b.imag));
}

/*
 * Normalize a complex number's magnitude to 1
 */
static inline COMP comp_normalize(COMP a){
	COMP b;
	float av = sqrtf((a.real*a.real)+(a.imag*a.imag));
	b.real = a.real/av;
	b.imag = a.imag/av;
	return b;
}


/*---------------------------------------------------------------------------*\

  FUNCTION....: fsk_create_hbr
  AUTHOR......: Brady O'Brien
  DATE CREATED: 11 February 2016
  
  Create and initialize an instance of the FSK modem. Returns a pointer
  to the modem state/config struct. One modem config struct may be used
  for both mod and demod. returns NULL on failure.

\*---------------------------------------------------------------------------*/

struct FSK * fsk_create_hbr(int Fs, int Rs,int P,int M, int tx_f1, int tx_fs)
{
    struct FSK *fsk;
    int i;
    int memold;
    int Ndft = 0;
    /* Number of symbols in a processing frame */
    int nsyms = 48;
    /* Check configuration validity */
    assert(Fs > 0 );
    assert(Rs > 0 );
    assert(tx_f1 > 0);
    assert(tx_fs > 0);
    assert(P > 0);
    /* Ts (Fs/Rs) must be an integer */
    assert( (Fs%Rs) == 0 );
    /* Ts/P (Fs/Rs/P) must be an integer */
    assert( ((Fs/Rs)%P) == 0 );
    assert( M==2 || M==4);
    
    fsk = (struct FSK*) malloc(sizeof(struct FSK));
    if(fsk == NULL) return NULL;
     
    
    /* Set constant config parameters */
    fsk->Fs = Fs;
    fsk->Rs = Rs;
    fsk->Ts = Fs/Rs;
    fsk->N = fsk->Ts*nsyms;
    fsk->P = P;
    fsk->Nsym = nsyms;
    fsk->Nmem = fsk->N+(2*fsk->Ts);
    fsk->f1_tx = tx_f1;
    fsk->fs_tx = tx_fs;
    fsk->nin = fsk->N;
    fsk->mode = M==2 ? MODE_2FSK : MODE_4FSK;
    fsk->Nbits = M==2 ? fsk->Nsym : fsk->Nsym*2;
    
    /* Find smallest 2^N value that fits Fs for efficient FFT */
    /* It would probably be better to use KISS-FFt's routine here */
    for(i=1; i; i<<=1)
        if((fsk->N)&i)
            Ndft = i;
    
    fsk->Ndft = Ndft;
    
    fsk->est_min = Rs/2;
    if(fsk->est_min<0) fsk->est_min = 0;
    
    fsk->est_max = (Fs/2)-Rs;
    
    fsk->est_space = Rs-(Rs/5);
    
    /* Set up rx state */
    fsk->phi1_c = comp_exp_j(0);
    fsk->phi2_c = comp_exp_j(0);
    fsk->phi3_c = comp_exp_j(0);
    fsk->phi4_c = comp_exp_j(0);
    
    fsk->phi1_c.real = 0;
    fsk->phi1_c.imag = 1;
    
    memold = (4*fsk->Ts);
    
    fsk->nstash = memold; 
    fsk->samp_old = (float*) malloc(sizeof(float)*memold);
    if(fsk->samp_old == NULL){
        free(fsk);
        return NULL;
    }
    
    for(i=0;i<memold;i++)fsk->samp_old[i]=0;
    
    fsk->fft_cfg = kiss_fftr_alloc(fsk->Ndft,0,NULL,NULL);
    if(fsk->fft_cfg == NULL){
        free(fsk->samp_old);
        free(fsk);
        return NULL;
    }
    
    fsk->fft_est = (float*)malloc(sizeof(float)*fsk->Ndft/2);
    if(fsk->fft_est == NULL){
        free(fsk->samp_old);
        free(fsk->fft_cfg);
        free(fsk);
        return NULL;
    }
    
    for(i=0;i<fsk->Ndft/2;i++)fsk->fft_est[i] = 0;
    
    fsk->norm_rx_timing = 0;
    
    /* Set up tx state */
    fsk->tx_phase_c = comp_exp_j(0);
    
    /* Set up demod stats */
    fsk->EbNodB = 0;
    fsk->f1_est = 0;
    fsk->f2_est = 0;
    fsk->f3_est = 0;
    fsk->f4_est = 0;    
    fsk->ppm = 0;

    fsk->stats = NULL;
    
    return fsk;
}

#define HORUS_MIN 800
#define HORUS_MAX 2500
#define HORUS_MIN_SPACING 100

/*---------------------------------------------------------------------------*\

  FUNCTION....: fsk_create
  AUTHOR......: Brady O'Brien
  DATE CREATED: 7 January 2016
  
  Create and initialize an instance of the FSK modem. Returns a pointer
  to the modem state/config struct. One modem config struct may be used
  for both mod and demod. returns NULL on failure.

\*---------------------------------------------------------------------------*/

struct FSK * fsk_create(int Fs, int Rs,int M, int tx_f1, int tx_fs)
{
    struct FSK *fsk;
    int i;
    int Ndft = 0;
    int memold;
    
    /* Check configuration validity */
    assert(Fs > 0 );
    assert(Rs > 0 );
    assert(tx_f1 > 0);
    assert(tx_fs > 0);
    assert(horus_P > 0);
    /* Ts (Fs/Rs) must be an integer */
    assert( (Fs%Rs) == 0 );
    /* Ts/P (Fs/Rs/P) must be an integer */
    assert( ((Fs/Rs)%horus_P) == 0 );
    assert( M==2 || M==4);
    
    fsk = (struct FSK*) malloc(sizeof(struct FSK));
    if(fsk == NULL) return NULL;
     
    Ndft = 1024;
    
    /* Set constant config parameters */
    fsk->Fs = Fs;
    fsk->Rs = Rs;
    fsk->Ts = Fs/Rs;
    fsk->N = Fs;
    fsk->P = horus_P;
    fsk->Nsym = fsk->N/fsk->Ts;
    fsk->Ndft = Ndft;
    fsk->Nmem = fsk->N+(2*fsk->Ts);
    fsk->f1_tx = tx_f1;
    fsk->fs_tx = tx_fs;
    fsk->nin = fsk->N;
    fsk->mode = M==2 ? MODE_2FSK : MODE_4FSK;
    fsk->Nbits = M==2 ? fsk->Nsym : fsk->Nsym*2;
    fsk->est_min = HORUS_MIN;
    fsk->est_max = HORUS_MAX;
    fsk->est_space = HORUS_MIN_SPACING;
    
    /* Set up rx state */
    fsk->phi1_c = comp_exp_j(0);
    fsk->phi2_c = comp_exp_j(0);
    fsk->phi3_c = comp_exp_j(0);
    fsk->phi4_c = comp_exp_j(0);
    
    fsk->phi1_c.real = 0;
    fsk->phi1_c.imag = 1;
    
    memold = (4*fsk->Ts);
    
    fsk->nstash = memold; 
    fsk->samp_old = (float*) malloc(sizeof(float)*memold);
    if(fsk->samp_old == NULL){
        free(fsk);
        return NULL;
    }
    
    for(i=0;i<memold;i++)fsk->samp_old[i]=0;
    
    fsk->fft_cfg = kiss_fftr_alloc(Ndft,0,NULL,NULL);
    if(fsk->fft_cfg == NULL){
        free(fsk->samp_old);
        free(fsk);
        return NULL;
    }
    
    fsk->fft_est = (float*)malloc(sizeof(float)*fsk->Ndft/2);
    if(fsk->fft_est == NULL){
        free(fsk->samp_old);
        free(fsk->fft_cfg);
        free(fsk);
        return NULL;
    }
    
    for(i=0;i<Ndft/2;i++)fsk->fft_est[i] = 0;
    
    fsk->norm_rx_timing = 0;
    
    /* Set up tx state */
    fsk->tx_phase_c = comp_exp_j(0);
    
    /* Set up demod stats */
    fsk->EbNodB = 0;
    fsk->f1_est = 0;
    fsk->f2_est = 0;
    fsk->f3_est = 0;
    fsk->f4_est = 0;    
    fsk->ppm = 0;

    fsk->stats = NULL;
    
    return fsk;
}


void fsk_set_nsym(struct FSK *fsk,int nsyms){
    assert(nsyms>0);
    int Ndft,i;
    Ndft = 0;
    
    /* Set constant config parameters */
    fsk->N = fsk->Ts*nsyms;
    fsk->Nsym = nsyms;
    fsk->Nmem = fsk->N+(2*fsk->Ts);
    fsk->nin = fsk->N;
    fsk->Nbits = fsk->mode==2 ? fsk->Nsym : fsk->Nsym*2;
    
    /* Find smallest 2^N value that fits Fs for efficient FFT */
    /* It would probably be better to use KISS-FFt's routine here */
    for(i=1; i; i<<=1)
        if((fsk->N)&i)
            Ndft = i;
    
    fsk->Ndft = Ndft;
    
    free(fsk->fft_cfg);
    free(fsk->fft_est);
    
    fsk->fft_cfg = kiss_fftr_alloc(Ndft,0,NULL,NULL);
    fsk->fft_est = (float*)malloc(sizeof(float)*fsk->Ndft/2);
    
    for(i=0;i<Ndft/2;i++)fsk->fft_est[i] = 0;
    
}

uint32_t fsk_nin(struct FSK *fsk){
    return (uint32_t)fsk->nin;
}

void fsk_destroy(struct FSK *fsk){
    free(fsk->fft_cfg);
    free(fsk->samp_old);
    free(fsk);
}

void fsk_setup_modem_stats(struct FSK *fsk,struct MODEM_STATS *stats){
    fsk->stats = stats;
}


/*
 * Internal function to estimate the frequencies of the two tones within a block of samples.
 * This is split off because it is fairly complicated, needs a bunch of memory, and probably
 * takes more cycles than the rest of the demod.
 * Parameters:
 * fsk - FSK struct from demod containing FSK config
 * fsk_in - block of samples in this demod cycles, must be nin long
 * freqs - Array for the estimated frequencies
 * M - number of frequency peaks to find
 */
void fsk_demod_freq_est(struct FSK *fsk, float fsk_in[],float *freqs,int M){
    int Ndft = fsk->Ndft;
    int Fs = fsk->Fs;
    int nin = fsk->nin;
    int i,j;
    int fft_samps;
    float hann;
    float max;
    float tc;
    int imax;
    kiss_fftr_cfg fft_cfg = fsk->fft_cfg;
    int freqi[M];
    int f_min,f_max,f_zero;
    /* Array to do complex FFT from using kiss_fft */
    /* It'd probably make more sense here to use kiss_fftr */
    
    #ifdef DEMOD_ALLOC_STACK
    kiss_fft_scalar *fftin  = (kiss_fft_scalar*)alloca(sizeof(kiss_fft_scalar)*Ndft);
    kiss_fft_cpx    *fftout = (kiss_fft_cpx*)   alloca(sizeof(kiss_fft_cpx)*(Ndft/2)+1);
    #else
    kiss_fft_scalar *fftin  = (kiss_fft_scalar*)malloc(sizeof(kiss_fft_scalar)*Ndft);
    kiss_fft_cpx    *fftout = (kiss_fft_cpx*)   malloc(sizeof(kiss_fft_cpx)*((Ndft/2)+1));
    #endif

    fft_samps = Ndft;
    
    f_min  = (fsk->est_min*Ndft)/Fs;
    f_max  = (fsk->est_max*Ndft)/Fs;
    f_zero = (fsk->est_space*Ndft)/Fs;
  
    /* scale averaging time constant based on number of samples */
    tc = 0.95*Ndft/Fs;
    
    int fft_loops = nin/Ndft;
    for(j=0; j<fft_loops; j++){
    /* Copy FSK buffer into reals of FFT buffer and apply a hann window */
		for(i=0; i<fft_samps; i++){
			hann = 1-cosf((2*M_PI*(float)(i))/((float)fft_samps-1));
			
			fftin[i] = (kiss_fft_scalar)0.5*hann*fsk_in[i+Ndft*j];
		}
		/* Zero out the remaining slots */
		for(; i<Ndft;i++){
			fftin[i] = 0;
		}
		
		/* Do the FFT */
		kiss_fftr(fft_cfg,fftin,fftout);
		
		/* Find the magnitude^2 of each freq slot and stash away in the real
		* value, so this only has to be done once. Since we're only comparing
		* these values and only need the mag of 2 points, we don't need to do
		* a sqrt to each value */
		for(i=0; i<Ndft/2; i++){
			fftout[i].r = (fftout[i].r*fftout[i].r) + (fftout[i].i*fftout[i].i) ;
		}
		
		/* Zero out the minimum and maximum ends */
		for(i=0; i<f_min; i++){
			fftout[i].r = 0;
		}
		for(i=f_max-1; i<Ndft/2; i++){
			fftout[i].r = 0;
		}
		/* Mix back in with the previous fft block */
		/* Copy new fft est into imag of fftout for frequency divination below */
		for(i=0; i<Ndft/2; i++){
			fsk->fft_est[i] = (fsk->fft_est[i]*(1-tc)) + (sqrtf(fftout[i].r)*tc);
			fftout[i].i = fsk->fft_est[i];
		}
	}
	
    modem_probe_samp_f("t_fft_est",fsk->fft_est,Ndft/2);
    
    max = 0;
    /* Find the M frequency peaks here */
    for(i=0; i<M; i++){
		imax = 0;
		max = 0;
		for(j=0;j<Ndft/2;j++){
			if(fftout[j].i > max){
				max = fftout[j].i;
				imax = j;
			}
		}
		/* Blank out FMax +/-Fspace/2 */
		f_min = imax - f_zero;
		f_min = f_min < 0 ? 0 : f_min;
		f_max = imax + f_zero;
		f_max = f_max > Ndft ? Ndft : f_max;
		for(j=f_min; j<f_max; j++)
			fftout[j].i = 0;
		
		/* Stick the freq index on the list */
		freqi[i] = imax;
	}
	
	/* Gnome sort the freq list */
	/* My favorite sort of sort*/
	i = 1;
	while(i<M){
		if(freqi[i] >= freqi[i-1]) i++;
		else{
			j = freqi[i];
			freqi[i] = freqi[i-1];
			freqi[i-1] = j;
			if(i>1) i--;
		}
	}

	/* Convert freqs from indices to frequencies */
	for(i=0; i<M; i++){
		freqs[i] = (float)(freqi[i])*((float)Fs/(float)Ndft);
	}
    #ifndef DEMOD_ALLOC_STACK
    free(fftin);
    free(fftout);
    #endif
}

void fsk2_demod(struct FSK *fsk, uint8_t rx_bits[], float fsk_in[]){
    int N = fsk->N;
    int Ts = fsk->Ts;
    int Rs = fsk->Rs;
    int Fs = fsk->Fs;
    int nsym = fsk->Nsym;
    int nin = fsk->nin;
    int P = fsk->P;
    int Nmem = fsk->Nmem;
    int M = fsk->mode;
    int i,j,dc_i,cbuf_i;
    float ft1;
    int nstash = fsk->nstash;
    COMP *f1_int, *f2_int;
    COMP t1,t2;
    COMP phi1_c = fsk->phi1_c;
    COMP phi2_c = fsk->phi2_c;
    COMP phi_ft;
    int nold = Nmem-nin;
    COMP dphi1,dphi2;
    COMP dphift;
    float rx_timing,norm_rx_timing,old_norm_rx_timing,d_norm_rx_timing,appm;
    int using_old_samps;
    float *sample_src;
    COMP *f1_intbuf,*f2_intbuf;
    float f_est[M],fc_avg,fc_tx;
    float meanebno,stdebno,eye_max;
    int neyesamp,neyeoffset;
    
    /* Estimate tone frequencies */
    fsk_demod_freq_est(fsk,fsk_in,f_est,M);
    modem_probe_samp_f("t_f_est",f_est,M);
    
    /* allocate memory for the integrated samples */
    #ifdef DEMOD_ALLOC_STACK
    /* allocate memory for the integrated samples */
    /* Note: This must be kept after fsk_demod_freq_est for memory usage reasons */
    f1_int = (COMP*) alloca(sizeof(COMP)*(nsym+1)*P);
    f2_int = (COMP*) alloca(sizeof(COMP)*(nsym+1)*P);
    
    /* Allocate circular buffers for integration */
    f1_intbuf = (COMP*) alloca(sizeof(COMP)*Ts);
    f2_intbuf = (COMP*) alloca(sizeof(COMP)*Ts);
    #else
    f1_int = (COMP*) malloc(sizeof(COMP)*(nsym+1)*P);
    f2_int = (COMP*) malloc(sizeof(COMP)*(nsym+1)*P);
    
    f1_intbuf = (COMP*) malloc(sizeof(COMP)*Ts);
    f2_intbuf = (COMP*) malloc(sizeof(COMP)*Ts);
    #endif
    
    /* If this is the first run, we won't have any valid f_est */
    if(fsk->f1_est<1){
		fsk->f1_est = f_est[0];
		fsk->f2_est = f_est[1];
	}
    
    /* Back the stored phase off to account for re-integraton of old samples */
    dphi1 = comp_exp_j(-2*(Nmem-nin-(Ts/P))*M_PI*((fsk->f1_est)/(float)(Fs)));
    dphi2 = comp_exp_j(-2*(Nmem-nin-(Ts/P))*M_PI*((fsk->f2_est)/(float)(Fs)));

    phi1_c = cmult(dphi1,phi1_c);
    phi2_c = cmult(dphi2,phi2_c);

    /* Figure out how much to nudge each sample downmixer for every sample */
    dphi1 = comp_exp_j(2*M_PI*((fsk->f1_est)/(float)(Fs)));
    dphi2 = comp_exp_j(2*M_PI*((fsk->f2_est)/(float)(Fs)));
    
    dc_i = 0;
    cbuf_i = 0;
    sample_src = &(fsk->samp_old[nstash-nold]);
    using_old_samps = 1;
    /* Pre-fill integration buffer */
    for(dc_i=0; dc_i<Ts-(Ts/P); dc_i++){
        /* Switch sample source to new samples when we run out of old ones */
        if(dc_i>=nold && using_old_samps){
            sample_src = &fsk_in[0];
            dc_i = 0;
            using_old_samps = 0;
            
            /* Recalculate delta-phi after switching to new sample source */
            phi1_c = comp_normalize(phi1_c);
            phi2_c = comp_normalize(phi2_c);
            dphi1 = comp_exp_j(2*M_PI*(f_est[0]/(float)(Fs)));
            dphi2 = comp_exp_j(2*M_PI*(f_est[1]/(float)(Fs)));
        }
        /* Downconvert and place into integration buffer */
        f1_intbuf[dc_i]=fcmult(sample_src[dc_i],phi1_c);
        f2_intbuf[dc_i]=fcmult(sample_src[dc_i],phi2_c);

        modem_probe_samp_c("t_f1_dc",&f1_intbuf[dc_i],1);
        modem_probe_samp_c("t_f2_dc",&f2_intbuf[dc_i],1);
        /* Spin downconversion phases */
        phi1_c = cmult(phi1_c,dphi1);
        phi2_c = cmult(phi2_c,dphi2);
    }
    cbuf_i = dc_i;
    
    /* Integrate over Ts at offsets of Ts/P */
    for(i=0; i<(nsym+1)*P; i++){
        /* Downconvert and Place Ts/P samples in the integration buffers */
        for(j=0; j<(Ts/P); j++,dc_i++){
            /* Switch sample source to new samples when we run out of old ones */
            if(dc_i>=nold && using_old_samps){
                sample_src = &fsk_in[0];
                dc_i = 0;
                using_old_samps = 0;
                
				/* Recalculate delta-phi after switching to new sample source */
				phi1_c = comp_normalize(phi1_c);
				phi2_c = comp_normalize(phi2_c);
				dphi1 = comp_exp_j(2*M_PI*((f_est[0])/(float)(Fs)));
				dphi2 = comp_exp_j(2*M_PI*((f_est[1])/(float)(Fs)));
            }
            /* Downconvert and place into integration buffer */
            f1_intbuf[cbuf_i+j]=fcmult(sample_src[dc_i],phi1_c);
            f2_intbuf[cbuf_i+j]=fcmult(sample_src[dc_i],phi2_c);
    
            modem_probe_samp_c("t_f1_dc",&f1_intbuf[cbuf_i+j],1);
            modem_probe_samp_c("t_f2_dc",&f2_intbuf[cbuf_i+j],1);
            /* Spin downconversion phases */
            phi1_c = cmult(phi1_c,dphi1);
            phi2_c = cmult(phi2_c,dphi2);
            
        }
        
        /* Dump internal samples */
        
        cbuf_i += Ts/P;
        if(cbuf_i>=Ts) cbuf_i = 0;
        
        /* Integrate over the integration buffers, save samples */
        t1 = t2 = comp0();
        for(j=0; j<Ts; j++){
            t1 = cadd(t1,f1_intbuf[j]);
            t2 = cadd(t2,f2_intbuf[j]);
        }
        f1_int[i] = t1;
        f2_int[i] = t2;
        
    }
    
	fsk->phi1_c = phi1_c;
    fsk->phi2_c = phi2_c;
    
	fsk->f1_est = f_est[0];
	fsk->f2_est = f_est[1];

    /* Stash samples away in the old sample buffer for the next round of bit getting */
    memcpy((void*)&(fsk->samp_old[0]),(void*)&(fsk_in[nin-nstash]),sizeof(float)*nstash);
    
    /* Fine Timing Estimation */
    /* Apply magic nonlinearity to f1_int and f2_int, shift down to 0, 
     * exract angle */
     
    /* Figure out how much to spin the oscillator to extract magic spectral line */
    dphift = comp_exp_j(2*M_PI*((float)(Rs)/(float)(P*Rs)));
    phi_ft.real = 1;
    phi_ft.imag = 0;
    t1=comp0();
    for(i=0; i<(nsym+1)*P; i++){
        /* Get abs^2 of fx_int[i], and add 'em */
        ft1  = (f1_int[i].real*f1_int[i].real) + (f1_int[i].imag*f1_int[i].imag);
        ft1 += (f2_int[i].real*f2_int[i].real) + (f2_int[i].imag*f2_int[i].imag);
        
        /* Down shift and accumulate magic line */
        t1 = cadd(t1,fcmult(ft1,phi_ft));

        /* Spin the oscillator for the magic line shift */
        phi_ft = cmult(phi_ft,dphift);
    }
    /* Get the magic angle */
    norm_rx_timing =  atan2f(t1.imag,t1.real)/(2*M_PI);
    rx_timing = norm_rx_timing*(float)P;
    
    old_norm_rx_timing = fsk->norm_rx_timing;
    fsk->norm_rx_timing = norm_rx_timing;
    
    /* Estimate sample clock offset */
    d_norm_rx_timing = norm_rx_timing - old_norm_rx_timing;
    
    /* Filter out big jumps in due to nin change */
    if(fabsf(d_norm_rx_timing) < .2){
        appm = 1e6*d_norm_rx_timing/(float)nsym;
        fsk->ppm = .9*fsk->ppm + .1*appm;
    }
    
    /* Figure out how many samples are needed the next modem cycle */
    if(norm_rx_timing > 0.25){
        fsk->nin = N+Ts/2;
    }
    else if(norm_rx_timing < -0.25){
        fsk->nin = N-Ts/2;
    }
    else
        fsk->nin = N;
    
    modem_probe_samp_f("t_norm_rx_timing",&(norm_rx_timing),1);
    modem_probe_samp_i("t_nin",&(fsk->nin),1);
    
    /* Re-sample the integrators with linear interpolation magic */
    int low_sample = (int)floorf(rx_timing);
    float fract = rx_timing - (float)low_sample;
    int high_sample = (int)ceilf(rx_timing);
 
	/* Vars for finding the max-of-4 for each bit */
	float tmax[2];
    
    #ifdef EST_EBNO
    meanebno = 0;
    stdebno = 0;
    #endif
  
    /* FINALLY, THE BITS */
    /* also, resample fx_int */
    for(i=0; i<nsym; i++){
        int st = (i+1)*P;
        t1 =         fcmult(1-fract,f1_int[st+ low_sample]);
        t1 = cadd(t1,fcmult(  fract,f1_int[st+high_sample]));
        t2 =         fcmult(1-fract,f2_int[st+ low_sample]);
        t2 = cadd(t2,fcmult(  fract,f2_int[st+high_sample]));
        
        /* Figure mag^2 of each resampled fx_int */
        tmax[0] = (t1.real*t1.real) + (t1.imag*t1.imag);
        tmax[1] = (t2.real*t2.real) + (t2.imag*t2.imag);
        rx_bits[i] = (tmax[1]>tmax[0])?1:0;
        
        /* Accumulate resampled int magnitude for EbNodB estimation */
        /* Standard deviation is calculated by algorithm devised by crafty soviets */
        #ifdef EST_EBNO
        /* Accumulate the square of the sampled value */
        ft1 = tmax[ (tmax[1]>tmax[0]) ];
        stdebno += ft1;
        
        /* Figure the abs value of the max tone */
        meanebno += sqrtf(ft1);
        #endif
        /* Soft output goes here */
    }
    
    #ifdef EST_EBNO
    /* Calculate mean for EbNodB estimation */
    meanebno = meanebno/(float)nsym;
    
    /* Calculate the std. dev for EbNodB estimate */
    stdebno = (stdebno/(float)nsym) - (meanebno*meanebno);
    stdebno = sqrt(stdebno);
    
    fsk->EbNodB = -6+(20*log10f((1e-6+meanebno)/(1e-6+stdebno)));
    #else
    fsk->EbNodB = 1;
    #endif
    
    /* Write some statistics out to the stats struct, if present */
    if( fsk->stats != NULL ){
        /* Save clock offset in ppm */
        fsk->stats->clock_offset = fsk->ppm;
        
        /* Calculate and save SNR from EbNodB estimate */
        fsk->stats->snr_est = .5*fsk->stats->snr_est + .5*fsk->EbNodB;//+ 10*log10f(((float)Rs)/((float)Rs*M));
        
        /* Save rx timing */
        fsk->stats->rx_timing = (float)rx_timing;
        
        /* Estimate and save frequency offset */
        fc_avg = (f_est[0]+f_est[1])/2;
        fc_tx = (fsk->f1_tx+fsk->f1_tx+fsk->fs_tx)/2;
        fsk->stats->foff = fc_tx-fc_avg;
    
        /* Take a sample for the eye diagrams */
        neyesamp = fsk->stats->neyesamp = P*2;
        neyeoffset = high_sample+1+(P*28);
        
        fsk->stats->neyetr = fsk->mode*3;
        for(j=0; j<neyesamp; j++)
            fsk->stats->rx_eye[0][j] = cabsolute(f1_int[neyeoffset+j]);
        for(j=0; j<neyesamp; j++)                       
            fsk->stats->rx_eye[1][j] = cabsolute(f2_int[neyeoffset+j]);
        for(j=0; j<neyesamp; j++)                      
            fsk->stats->rx_eye[2][j] = cabsolute(f1_int[neyeoffset+neyesamp+j]);
        for(j=0; j<neyesamp; j++)                                 
            fsk->stats->rx_eye[3][j] = cabsolute(f2_int[neyeoffset+neyesamp+j]);
        for(j=0; j<neyesamp; j++)                      
            fsk->stats->rx_eye[4][j] = cabsolute(f1_int[neyeoffset+2*neyesamp+j]);
        for(j=0; j<neyesamp; j++)                                 
            fsk->stats->rx_eye[5][j] = cabsolute(f2_int[neyeoffset+2*neyesamp+j]);    
        
        eye_max = 0;
        /* Normalize eye to +/- 1 */
        for(i=0; i<fsk->mode*3; i++)
            for(j=0; j<neyesamp; j++)
                if(fabsf(fsk->stats->rx_eye[i][j])>eye_max)
                    eye_max = fabsf(fsk->stats->rx_eye[i][j]);
        
        for(i=0; i<fsk->mode*3; i++)
            for(j=0; j<neyesamp; j++)
                fsk->stats->rx_eye[i][j] = fsk->stats->rx_eye[i][j]/eye_max;
        
        fsk->stats->nr = 0;
        fsk->stats->Nc = 0;
    }
    
    /* Dump some internal samples */
    modem_probe_samp_f("t_EbNodB",&(fsk->EbNodB),1);
    modem_probe_samp_f("t_ppm",&(fsk->ppm),1);
    modem_probe_samp_f("t_f1",&f_est[0],1);
    modem_probe_samp_f("t_f2",&f_est[1],1);
    modem_probe_samp_c("t_f1_int",f1_int,(nsym+1)*P);
    modem_probe_samp_c("t_f2_int",f2_int,(nsym+1)*P);
    modem_probe_samp_f("t_rx_timing",&(rx_timing),1);
    
    #ifndef DEMOD_ALLOC_STACK
    free(f1_int);
    free(f2_int);
    free(f1_intbuf);
    free(f2_intbuf);
    #endif
}

void fsk4_demod(struct FSK *fsk, uint8_t rx_bits[], float fsk_in[]){
    int N = fsk->N;
    int Ts = fsk->Ts;
    int Rs = fsk->Rs;
    int Fs = fsk->Fs;
    int nsym = fsk->Nsym;
    int nin = fsk->nin;
    int P = fsk->P;
    int Nmem = fsk->Nmem;
    int M = fsk->mode;
    int i,j,dc_i,cbuf_i;
    float ft1;
    int nstash = fsk->nstash;
    COMP *f1_int, *f2_int, *f3_int, *f4_int;
    COMP t1,t2,t3,t4;
    COMP phi1_c = fsk->phi1_c;
    COMP phi2_c = fsk->phi2_c;
    COMP phi3_c = fsk->phi3_c;
    COMP phi4_c = fsk->phi4_c;
    COMP phi_ft;
    int nold = Nmem-nin;
    COMP dphi1,dphi2,dphi3,dphi4;
    COMP dphift;
    float rx_timing,norm_rx_timing,old_norm_rx_timing,d_norm_rx_timing,appm;
    int using_old_samps;
    float *sample_src;
    COMP *f1_intbuf,*f2_intbuf,*f3_intbuf,*f4_intbuf;
    float f_est[M],fc_avg,fc_tx;
    float meanebno,stdebno,eye_max;
    int neyesamp,neyeoffset;
    
    /* Estimate tone frequencies */
    fsk_demod_freq_est(fsk,fsk_in,f_est,M);
    modem_probe_samp_f("t_f_est",f_est,M);

    #ifdef DEMOD_ALLOC_STACK
    /* allocate memory for the integrated samples */
    /* Note: This must be kept after fsk_demod_freq_est for memory usage reasons */
    f1_int = (COMP*) alloca(sizeof(COMP)*(nsym+1)*P);
    f2_int = (COMP*) alloca(sizeof(COMP)*(nsym+1)*P);
    f3_int = (COMP*) alloca(sizeof(COMP)*(nsym+1)*P);
    f4_int = (COMP*) alloca(sizeof(COMP)*(nsym+1)*P);
    
    /* Allocate circular buffers for integration */
    f1_intbuf = (COMP*) alloca(sizeof(COMP)*Ts);
    f2_intbuf = (COMP*) alloca(sizeof(COMP)*Ts);
    f3_intbuf = (COMP*) alloca(sizeof(COMP)*Ts);
    f4_intbuf = (COMP*) alloca(sizeof(COMP)*Ts);
    #else
    f1_int = (COMP*) malloc(sizeof(COMP)*(nsym+1)*P);
    f2_int = (COMP*) malloc(sizeof(COMP)*(nsym+1)*P);
    f3_int = (COMP*) malloc(sizeof(COMP)*(nsym+1)*P);
    f4_int = (COMP*) malloc(sizeof(COMP)*(nsym+1)*P);
    
    f1_intbuf = (COMP*) malloc(sizeof(COMP)*Ts);
    f2_intbuf = (COMP*) malloc(sizeof(COMP)*Ts);
    f3_intbuf = (COMP*) malloc(sizeof(COMP)*Ts);
    f4_intbuf = (COMP*) malloc(sizeof(COMP)*Ts);
    #endif
    /* If this is the first run, we won't have any valid f_est */
    if(fsk->f1_est<1){
		fsk->f1_est = f_est[0];
		fsk->f2_est = f_est[1];
		fsk->f3_est = f_est[2];
		fsk->f4_est = f_est[3];
	}

    /* Back the stored phase off to account for re-integraton of old samples */
    dphi1 = comp_exp_j(-2*(Nmem-nin-(Ts/P))*M_PI*((fsk->f1_est)/(float)(Fs)));
    dphi2 = comp_exp_j(-2*(Nmem-nin-(Ts/P))*M_PI*((fsk->f2_est)/(float)(Fs)));
    dphi3 = comp_exp_j(-2*(Nmem-nin-(Ts/P))*M_PI*((fsk->f3_est)/(float)(Fs)));
    dphi4 = comp_exp_j(-2*(Nmem-nin-(Ts/P))*M_PI*((fsk->f4_est)/(float)(Fs)));
    
    phi1_c = cmult(dphi1,phi1_c);
    phi2_c = cmult(dphi2,phi2_c);
    phi3_c = cmult(dphi3,phi3_c);
    phi4_c = cmult(dphi4,phi4_c);

    /* Figure out how much to nudge each sample downmixer for every sample */
    dphi1 = comp_exp_j(2*M_PI*((fsk->f1_est)/(float)(Fs)));
    dphi2 = comp_exp_j(2*M_PI*((fsk->f2_est)/(float)(Fs)));
    dphi3 = comp_exp_j(2*M_PI*((fsk->f3_est)/(float)(Fs)));
    dphi4 = comp_exp_j(2*M_PI*((fsk->f4_est)/(float)(Fs)));

    dc_i = 0;
    cbuf_i = 0;
    sample_src = &(fsk->samp_old[nstash-nold]);
    using_old_samps = 1;
    
    /* Pre-fill integration buffer */
    for(dc_i=0; dc_i<Ts-(Ts/P); dc_i++){
        /* Switch sample source to new samples when we run out of old ones */
        if(dc_i>=nold && using_old_samps){
            sample_src = &fsk_in[0];
            dc_i = 0;
            using_old_samps = 0;
            
            /* Recalculate delta-phi after switching to new sample source */
            phi1_c = comp_normalize(phi1_c);
            phi2_c = comp_normalize(phi2_c);
            phi3_c = comp_normalize(phi3_c);
            phi4_c = comp_normalize(phi4_c);
            dphi1 = comp_exp_j(2*M_PI*((f_est[0])/(float)(Fs)));
            dphi2 = comp_exp_j(2*M_PI*((f_est[1])/(float)(Fs)));
            dphi3 = comp_exp_j(2*M_PI*((f_est[2])/(float)(Fs)));
            dphi4 = comp_exp_j(2*M_PI*((f_est[3])/(float)(Fs)));
        }
        /* Downconvert and place into integration buffer */
        f1_intbuf[dc_i]=fcmult(sample_src[dc_i],phi1_c);
        f2_intbuf[dc_i]=fcmult(sample_src[dc_i],phi2_c);
        f3_intbuf[dc_i]=fcmult(sample_src[dc_i],phi3_c);
        f4_intbuf[dc_i]=fcmult(sample_src[dc_i],phi4_c);

        modem_probe_samp_c("t_f1_dc",&f1_intbuf[dc_i],1);
        modem_probe_samp_c("t_f2_dc",&f2_intbuf[dc_i],1);
        modem_probe_samp_c("t_f3_dc",&f3_intbuf[dc_i],1);
        modem_probe_samp_c("t_f4_dc",&f4_intbuf[dc_i],1);
        /* Spin downconversion phases */
        phi1_c = cmult(phi1_c,dphi1);
        phi2_c = cmult(phi2_c,dphi2);
        phi3_c = cmult(phi3_c,dphi3);
        phi4_c = cmult(phi4_c,dphi4);
    }
    cbuf_i = dc_i;
    
    /* Integrate over Ts at offsets of Ts/P */
    for(i=0; i<(nsym+1)*P; i++){
        /* Downconvert and Place Ts/P samples in the integration buffers */
        for(j=0; j<(Ts/P); j++,dc_i++){
            /* Switch sample source to new samples when we run out of old ones */
            if(dc_i>=nold && using_old_samps){
                sample_src = &fsk_in[0];
                dc_i = 0;
                using_old_samps = 0;
                
				/* Recalculate delta-phi after switching to new sample source */
				phi1_c = comp_normalize(phi1_c);
				phi2_c = comp_normalize(phi2_c);
				phi3_c = comp_normalize(phi3_c);
				phi4_c = comp_normalize(phi4_c);
				dphi1 = comp_exp_j(2*M_PI*((f_est[0])/(float)(Fs)));
				dphi2 = comp_exp_j(2*M_PI*((f_est[1])/(float)(Fs)));
				dphi3 = comp_exp_j(2*M_PI*((f_est[2])/(float)(Fs)));
				dphi4 = comp_exp_j(2*M_PI*((f_est[3])/(float)(Fs)));
            }
            /* Downconvert and place into integration buffer */
            f1_intbuf[cbuf_i+j]=fcmult(sample_src[dc_i],phi1_c);
            f2_intbuf[cbuf_i+j]=fcmult(sample_src[dc_i],phi2_c);
            f3_intbuf[cbuf_i+j]=fcmult(sample_src[dc_i],phi3_c);
            f4_intbuf[cbuf_i+j]=fcmult(sample_src[dc_i],phi4_c);
    
            modem_probe_samp_c("t_f1_dc",&f1_intbuf[cbuf_i+j],1);
            modem_probe_samp_c("t_f2_dc",&f2_intbuf[cbuf_i+j],1);
            modem_probe_samp_c("t_f3_dc",&f3_intbuf[cbuf_i+j],1);
            modem_probe_samp_c("t_f4_dc",&f4_intbuf[cbuf_i+j],1);
            /* Spin downconversion phases */
            phi1_c = cmult(phi1_c,dphi1);
            phi2_c = cmult(phi2_c,dphi2);
            phi3_c = cmult(phi3_c,dphi3);
            phi4_c = cmult(phi4_c,dphi4);
            
        }
        
        /* Dump internal samples */
        
        cbuf_i += Ts/P;
        if(cbuf_i>=Ts) cbuf_i = 0;
        /* Integrate over the integration buffers, save samples */
        t1 = t2 = t3 = t4 = comp0();
        for(j=0; j<Ts; j++){
            t1 = cadd(t1,f1_intbuf[j]);
            t2 = cadd(t2,f2_intbuf[j]);
            t3 = cadd(t3,f3_intbuf[j]);
            t4 = cadd(t4,f4_intbuf[j]);
        }
        f1_int[i] = t1;
        f2_int[i] = t2;
        f3_int[i] = t3;
        f4_int[i] = t4;
        
    }

    fsk->phi1_c = phi1_c;
	fsk->phi2_c = phi2_c;
	fsk->phi3_c = phi3_c;
	fsk->phi4_c = phi4_c;

	fsk->f1_est = f_est[0];
	fsk->f2_est = f_est[1];
	fsk->f3_est = f_est[2];
	fsk->f4_est = f_est[3];

    /* Stash samples away in the old sample buffer for the next round of bit getting */
    memcpy((void*)&(fsk->samp_old[0]),(void*)&(fsk_in[nin-nstash]),sizeof(float)*nstash);
    
    /* Fine Timing Estimation */
    /* Apply magic nonlinearity to f1_int and f2_int, shift down to 0, 
     * exract angle */
     
    /* Figure out how much to spin the oscillator to extract magic spectral line */
    dphift = comp_exp_j(-2*M_PI*((float)(Rs)/(float)(P*Rs)));
    phi_ft.real = 1;
    phi_ft.imag = 0;
    t1=comp0();
    COMP c,y,t;
    c = comp0();
    t2 = comp0();
    for(i=0; i<(nsym+1)*P; i++){
        /* Get abs^2 of fx_int[i], and add 'em */
        ft1  = (f1_int[i].real*f1_int[i].real) + (f1_int[i].imag*f1_int[i].imag);
        ft1 += (f2_int[i].real*f2_int[i].real) + (f2_int[i].imag*f2_int[i].imag);
        ft1 += (f3_int[i].real*f3_int[i].real) + (f3_int[i].imag*f3_int[i].imag);
        ft1 += (f4_int[i].real*f4_int[i].real) + (f4_int[i].imag*f4_int[i].imag);
        
        /* Down shift and accumulate magic line */
        t1 = fcmult(ft1,phi_ft);
        y.real = t1.real-c.real;
        y.imag = t1.imag-c.imag;
        
        t.real = t2.real + y.real;
        t.imag = t2.imag + y.imag;
        
        c.real = (t.real-t2.real) - y.real;
        c.imag = (t.imag-t2.imag) - y.imag;
     
        t2 = cadd(t2,t1);
        
        /* Spin the oscillator for the magic line shift */
        phi_ft = cmult(phi_ft,dphift);
    }
    t1 = t2;
    /* Get the magic angle */
    norm_rx_timing =  -atan2f(t1.imag,t1.real)/(2*M_PI);
    rx_timing = norm_rx_timing*(float)P;
    
    old_norm_rx_timing = fsk->norm_rx_timing;
    fsk->norm_rx_timing = norm_rx_timing;
    
    /* Estimate sample clock offset */
    d_norm_rx_timing = norm_rx_timing - old_norm_rx_timing;
    
    /* Filter out big jumps in due to nin change */
    if(fabsf(d_norm_rx_timing) < .2){
        appm = 1e6*d_norm_rx_timing/(float)nsym;
        fsk->ppm = .9*fsk->ppm + .1*appm;
    }
    
    /* Figure out how many samples are needed the next modem cycle */
    if(norm_rx_timing > 0.25){
        fsk->nin = N+Ts/2;
    }
    else if(norm_rx_timing < -0.25){
        fsk->nin = N-Ts/2;
    }
    else
        fsk->nin = N;
    
    modem_probe_samp_f("t_norm_rx_timing",&(norm_rx_timing),1);
    modem_probe_samp_i("t_nin",&(fsk->nin),1);
    
    /* Re-sample the integrators with linear interpolation magic */
    int low_sample = (int)floorf(rx_timing);
    float fract = rx_timing - (float)low_sample;
    int high_sample = (int)ceilf(rx_timing);
 
	/* Vars for finding the max-of-4 for each bit */
	float tmax[4];
    float max = 0;
    int sym = 0;
    
    #ifdef EST_EBNO
    meanebno = 0;
    stdebno = 0;
    #endif
  
    /* FINALLY, THE BITS */
    /* also, resample fx_int */
    for(i=0; i<nsym; i++){
        int st = (i+1)*P;
        t1 =         fcmult(1-fract,f1_int[st+ low_sample]);
        t1 = cadd(t1,fcmult(  fract,f1_int[st+high_sample]));
        t2 =         fcmult(1-fract,f2_int[st+ low_sample]);
        t2 = cadd(t2,fcmult(  fract,f2_int[st+high_sample]));
        t3 =         fcmult(1-fract,f3_int[st+ low_sample]);
        t3 = cadd(t3,fcmult(  fract,f3_int[st+high_sample]));
        t4 =         fcmult(1-fract,f4_int[st+ low_sample]);
        t4 = cadd(t4,fcmult(  fract,f4_int[st+high_sample]));
        
        /* Figure mag^2 of each resampled fx_int */
        tmax[0] = (t1.real*t1.real) + (t1.imag*t1.imag);
        tmax[1] = (t2.real*t2.real) + (t2.imag*t2.imag);
        tmax[2] = (t3.real*t3.real) + (t3.imag*t3.imag);
        tmax[3] = (t4.real*t4.real) + (t4.imag*t4.imag);
        
        /* Find the maximum symbol */
        max = 0;
        sym = 0;
        for(j=0; j<4; j++){
			if(tmax[j]>max){
				sym = j;
				max = tmax[j];
			}
		}
        
        /* Turn into bits */
        rx_bits[(i*2)+1] = (sym&0x1);
        rx_bits[(i*2)  ] = (sym&0x2)>>1;
        
        /* Accumulate resampled int magnitude for EbNodB estimation */
        /* Standard deviation is calculated by algorithm devised by crafty soviets */
        #ifdef EST_EBNO
        /* Accumulate the square of the sampled value */
        ft1 = max;
        stdebno += ft1;
        
        /* Figure the abs value of the max tone */
        meanebno += sqrtf(ft1);
        #endif
        /* Soft output goes here */
    }
    
     #ifdef EST_EBNO
    /* Calculate mean for EbNodB estimation */
    meanebno = meanebno/(float)nsym;
    
    /* Calculate the std. dev for EbNodB estimate */
    stdebno = (stdebno/(float)nsym) - (meanebno*meanebno);
    stdebno = sqrt(stdebno);
    
    fsk->EbNodB = -6+(20*log10f((1e-6+meanebno)/(1e-6+stdebno)));
    #else
    fsk->EbNodB = 1;
    #endif
    
    /* Write some statistics out to the stats struct, if present */
    if( fsk->stats != NULL ){
        /* Save clock offset in ppm */
        fsk->stats->clock_offset = fsk->ppm;
        
        /* Calculate and save SNR from EbNodB estimate */
        fsk->stats->snr_est = .5*fsk->stats->snr_est + .5*fsk->EbNodB;//+ 10*log10f(((float)Rs)/((float)Rs*M));
        
        /* Save rx timing */
        fsk->stats->rx_timing = (float)rx_timing;
        
        /* Estimate and save frequency offset */
        fc_avg = (f_est[0]+f_est[1]+f_est[3]+f_est[2])/4;
        fc_tx = (fsk->f1_tx+fsk->f1_tx+fsk->fs_tx)/2;
        fsk->stats->foff = fc_tx-fc_avg;
    
        /* Take a sample for the eye diagrams */
        neyesamp = fsk->stats->neyesamp = P*2;
        neyeoffset = low_sample+1+(P*(nsym/4));
        fsk->stats->neyetr = fsk->mode*2;
        
        for(j=0; j<neyesamp; j++)
            fsk->stats->rx_eye[0][j] = cabsolute(f1_int[neyeoffset+j]);
        for(j=0; j<neyesamp; j++)                       
            fsk->stats->rx_eye[1][j] = cabsolute(f2_int[neyeoffset+j]);
        for(j=0; j<neyesamp; j++)
            fsk->stats->rx_eye[2][j] = cabsolute(f3_int[neyeoffset+j]);
        for(j=0; j<neyesamp; j++)                       
            fsk->stats->rx_eye[3][j] = cabsolute(f4_int[neyeoffset+j]);
        for(j=0; j<neyesamp; j++)                      
            fsk->stats->rx_eye[4][j] = cabsolute(f1_int[neyeoffset+neyesamp+j]);
        for(j=0; j<neyesamp; j++)                                 
            fsk->stats->rx_eye[5][j] = cabsolute(f2_int[neyeoffset+neyesamp+j]);
        for(j=0; j<neyesamp; j++)                      
            fsk->stats->rx_eye[6][j] = cabsolute(f3_int[neyeoffset+neyesamp+j]);
        for(j=0; j<neyesamp; j++)                                 
            fsk->stats->rx_eye[7][j] = cabsolute(f4_int[neyeoffset+neyesamp+j]);    
        
        eye_max = 0;
        /* Normalize eye to +/- 1 */
        for(i=0; i<fsk->mode*2; i++)
            for(j=0; j<neyesamp; j++)
                if(fabsf(fsk->stats->rx_eye[i][j])>eye_max)
                    eye_max = fabsf(fsk->stats->rx_eye[i][j]);
        
        for(i=0; i<fsk->mode*2; i++)
            for(j=0; j<neyesamp; j++)
                fsk->stats->rx_eye[i][j] = fsk->stats->rx_eye[i][j]/eye_max;
        
        fsk->stats->nr = 0;
        fsk->stats->Nc = 0;
    }
    
    /* Dump some internal samples */
    modem_probe_samp_f("t_EbNodB",&(fsk->EbNodB),1);
    modem_probe_samp_f("t_ppm",&(fsk->ppm),1);
    modem_probe_samp_f("t_f1",&f_est[0],1);
    modem_probe_samp_f("t_f2",&f_est[1],1);
    modem_probe_samp_f("t_f3",&f_est[2],1);
    modem_probe_samp_f("t_f4",&f_est[3],1);
    modem_probe_samp_c("t_f1_int",f1_int,(nsym+1)*P);
    modem_probe_samp_c("t_f2_int",f2_int,(nsym+1)*P);
    modem_probe_samp_c("t_f3_int",f3_int,(nsym+1)*P);
    modem_probe_samp_c("t_f4_int",f4_int,(nsym+1)*P);
    modem_probe_samp_f("t_rx_timing",&(rx_timing),1);

    #ifndef DEMOD_ALLOC_STACK
    free(f1_int);
    free(f2_int);
    free(f3_int);
    free(f4_int);
    free(f1_intbuf);
    free(f2_intbuf);
    free(f3_intbuf);
    free(f4_intbuf);
    #endif
}


void fsk_demod(struct FSK *fsk, uint8_t rx_bits[], float fsk_in[]){
	if(fsk->mode == 4){
		fsk4_demod(fsk,rx_bits,fsk_in);
	}else{
		fsk2_demod(fsk,rx_bits,fsk_in);
	}
}

void fsk_mod(struct FSK *fsk,float fsk_out[],uint8_t tx_bits[]){
    COMP tx_phase_c = fsk->tx_phase_c; /* Current complex TX phase */
    int f1_tx = fsk->f1_tx;         /* '0' frequency */
    int fs_tx = fsk->fs_tx;         /* space between frequencies */
    int Ts = fsk->Ts;               /* samples-per-symbol */
    int Fs = fsk->Fs;               /* sample freq */
    COMP dosc_f[4];                 /* phase shift per sample */
    COMP dph;                       /* phase shift of current bit */
    int i,j,sym;
    
    /* Figure out the amount of phase shift needed per sample */
    dosc_f[0] = comp_exp_j(2*M_PI*((float)(f1_tx        )/(float)(Fs)));
    dosc_f[1] = comp_exp_j(2*M_PI*((float)(f1_tx+fs_tx  )/(float)(Fs)));
    
    dosc_f[2] = comp_exp_j(2*M_PI*((float)(f1_tx+fs_tx*2)/(float)(Fs)));
    dosc_f[3] = comp_exp_j(2*M_PI*((float)(f1_tx+fs_tx*3)/(float)(Fs)));
    
    if(fsk->mode == 2){
		/* Outer loop through bits */
		for(i=0; i<fsk->Nsym; i++){
			/* select current bit phase shift */
			dph = tx_bits[i]==0?dosc_f[0]:dosc_f[1];
			for(j=0; j<Ts; j++){
				tx_phase_c = cmult(tx_phase_c,dph);
				fsk_out[i*Ts+j] = 2*tx_phase_c.real;
			}
		}
	}else {
		/* Same thing as above, but with more bits and phases */
		for(i=0; i<fsk->Nsym; i++){
			/* select current bit phase shift */
			sym = tx_bits[ i*2   ]==0?0:2;
			sym+= tx_bits[(i*2)+1]==0?0:1;
			dph = dosc_f[sym];
			for(j=0; j<Ts; j++){
				tx_phase_c = cmult(tx_phase_c,dph);
				fsk_out[i*Ts+j] = 2*tx_phase_c.real;
			}
		}
	}
    
    /* Normalize TX phase to prevent drift */
    tx_phase_c = comp_normalize(tx_phase_c);
    
    /* save TX phase */
    fsk->tx_phase_c = tx_phase_c;
    
}










