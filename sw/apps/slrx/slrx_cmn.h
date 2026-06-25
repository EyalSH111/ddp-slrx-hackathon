#ifndef _SLRX_CMN_H_
#define _SLRX_CMN_H_

#include <k5_libs.h>
#include <slr_lib.h>

#ifdef ALL_XON
#define CONV_XON
#define POOL_XON
#define LIN_XON
#endif

//------------------------------------------------------------------------------------------------------------

uint8_t relu_and_descale(int32_t x); 

#endif