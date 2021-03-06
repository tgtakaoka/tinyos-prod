/*
 * Copyright (c) 2012-2013 Eric B. Decker
 * Copyright (c) 2011 John Hopkins University
 * Copyright (c) 2011 Redslate Ltd.
 * Copyright (c) 2009-2010 People Power Co.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * - Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 *
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the
 *   distribution.
 *
 * - Neither the name of the copyright holders nor the names of
 *   its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL
 * THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "msp430usci.h"

/**
 * Core implementation for any USCI module present on an MSP430 chip.
 *
 * This module makes available the module-specific registers, along
 * with a small number of higher-level functions like generic USCI
 * chip configuration that are shared among the various modes of the
 * module.
 *
 * @author Peter A. Bigot <pab@peoplepowerco.com>
 * @author Derek Baker <derek@red-slate.co.uk>
 * @author Doug Carlson <carlson@cs.jhu.edu>
 * @author Marcus Chang <marcus.chang@gmail.com>
 * @author Eric B. Decker <cire831@gmail.com>
 *
 * Depending on the optimization level of the toolchain and which toolchain,
 * access may or may not be single instructions (ie. atomic).  When not sure
 * of exactly what instructions are being used one should use the default
 * which is to surround accesses with "atomic".
 *
 * The define MSP430_USCI_ATOMIC_LOWLEVEL is used to control whether accesses
 * are protected from interrupts (via "atomic").  If not defined, it will
 * default to "atomic".   To generated optimized accesses, define it to be
 * empty.  From your Makefile, you can do "CFLAGS += -DMSP430_USCI_ATOMIC_LOWLEVEL=".
 *
 * Any override will typically be done either in the platform's hardware.h
 * or in the applications "Makefile".
 *
 * WARNING: When MSP430_USCI_ATOMIC_LOWLEVEL is blank, this code makes the
 * assumption that access to the various registers occurs with single
 * instructions and thus is atomic.  It has been verified that with -Os
 * optimization, that indeed register access is via single instructions.
 * Other optimizations may not result in single instructions.  In those
 * cases, you should use the default value which causes "atomics" to protect
 * access from interrupts.
 *
 * If you turn off the atomic protection it is assumed that you know
 * what you are doing and will make sure the machine state is reasonable
 * for what you are doing.
 *
 * Also note that many of the fields in various registers shouldn't be
 * set unless the device (that is the module) is in reset.   See the
 * Users guide for details ie. SLAU208M for the x5 family cpus.
 */

#ifndef MSP430_USCI_ATOMIC_LOWLEVEL
#define MSP430_USCI_ATOMIC_LOWLEVEL atomic
#endif

generic module HplMsp430UsciP(
  /** Identifier for this USCI module, unique across (type, instance) pairs */
  uint8_t USCI_ID,
  /** Offset of UCmxCTLW0_ register for m=module_type and x=module_instance */
  unsigned int UCmxCTLW0_
) @safe() {
  provides {
    interface HplMsp430Usci as Usci;
    interface HplMsp430UsciInterrupts as Interrupts[ uint8_t mode ];
  }
  uses {
    interface HplMsp430UsciInterrupts as RawInterrupts;
    interface ArbiterInfo;
  }
}
implementation {

#define UCmxCTLW0  (*TCAST(volatile uint16_t* ONE, UCmxCTLW0_))
#define UCmxCTL1   (*TCAST(volatile uint8_t*  ONE, UCmxCTLW0_ + 0x00)) // yes, ctl1 is at offset zero
#define UCmxCTL0   (*TCAST(volatile uint8_t*  ONE, UCmxCTLW0_ + 0x01)) // and, ctl0 is at offset one
#define UCmxBRW    (*TCAST(volatile uint16_t* ONE, UCmxCTLW0_ + 0x06))
#define UCmxBR0    (*TCAST(volatile uint8_t*  ONE, UCmxCTLW0_ + 0x06))
#define UCmxBR1    (*TCAST(volatile uint8_t*  ONE, UCmxCTLW0_ + 0x07))
#define UCmxMCTL   (*TCAST(volatile uint8_t*  ONE, UCmxCTLW0_ + 0x08))
#define UCmxSTAT   (*TCAST(volatile uint8_t*  ONE, UCmxCTLW0_ + 0x0a))
#define UCmxRXBUF  (*TCAST(volatile uint8_t*  ONE, UCmxCTLW0_ + 0x0c))
#define UCmxTXBUF  (*TCAST(volatile uint8_t*  ONE, UCmxCTLW0_ + 0x0e))
#define UCmxABCTL  (*TCAST(volatile uint8_t*  ONE, UCmxCTLW0_ + 0x10))
#define UCmxI2COA  (*TCAST(volatile uint16_t* ONE, UCmxCTLW0_ + 0x10))
#define UCmxIRCTL  (*TCAST(volatile uint16_t* ONE, UCmxCTLW0_ + 0x12))
#define UCmxIRTCTL (*TCAST(volatile uint8_t*  ONE, UCmxCTLW0_ + 0x12))
#define UCmxIRRCTL (*TCAST(volatile uint8_t*  ONE, UCmxCTLW0_ + 0x13))
#define UCmxI2CSA  (*TCAST(volatile uint16_t* ONE, UCmxCTLW0_ + 0x12))
#define UCmxICTL   (*TCAST(volatile uint16_t* ONE, UCmxCTLW0_ + 0x1c))
#define UCmxIE     (*TCAST(volatile uint8_t*  ONE, UCmxCTLW0_ + 0x1c))
#define UCmxIFG    (*TCAST(volatile uint8_t*  ONE, UCmxCTLW0_ + 0x1d))
#define UCmxIV     (*TCAST(volatile uint16_t* ONE, UCmxCTLW0_ + 0x1e))

  async command uint8_t Usci.getModuleIdentifier()  { return USCI_ID; }

  async command uint16_t Usci.getCtlw0()            { return UCmxCTLW0; }
  async command uint8_t  Usci.getCtl0()             { return UCmxCTL0; }
  async command uint8_t  Usci.getCtl1()             { return UCmxCTL1; }

  async command void     Usci.setCtlw0(uint16_t v)  { UCmxCTLW0 = v; }
  async command void     Usci.setCtl0(uint8_t v)    { UCmxCTL0  = v; }
  async command void     Usci.setCtl1(uint8_t v)    { UCmxCTL1  = v; }

  async command void     Usci.orCtlw0(uint16_t v)   { MSP430_USCI_ATOMIC_LOWLEVEL UCmxCTLW0 |= v; }
  async command void     Usci.orCtl0(uint8_t v)     { MSP430_USCI_ATOMIC_LOWLEVEL UCmxCTL0  |= v; }
  async command void     Usci.orCtl1(uint8_t v)	    { MSP430_USCI_ATOMIC_LOWLEVEL UCmxCTL1  |= v; }

  async command void     Usci.andCtlw0(uint16_t v)  { MSP430_USCI_ATOMIC_LOWLEVEL UCmxCTLW0 &= v; }
  async command void     Usci.andCtl0(uint8_t v)    { MSP430_USCI_ATOMIC_LOWLEVEL UCmxCTL0  &= v; }
  async command void     Usci.andCtl1(uint8_t v)    { MSP430_USCI_ATOMIC_LOWLEVEL UCmxCTL1  &= v; }

  async command uint16_t Usci.getBrw()		    { return UCmxBRW; }
  async command uint8_t  Usci.getBr0()		    { return UCmxBR0; }
  async command uint8_t  Usci.getBr1()		    { return UCmxBR1; }

  async command void     Usci.setBrw(uint16_t v)    { UCmxBRW = v; }
  async command void     Usci.setBr0(uint8_t v)     { UCmxBR0 = v; }
  async command void     Usci.setBr1(uint8_t v)     { UCmxBR1 = v; }

  async command uint8_t  Usci.getMctl()		    { return UCmxMCTL; }
  async command void     Usci.setMctl(uint8_t v)    { UCmxMCTL = v; }
  async command uint8_t  Usci.getStat()		    { return UCmxSTAT; }
  async command void     Usci.setStat(uint8_t v)    { UCmxSTAT = v; }
  async command uint8_t  Usci.getRxbuf()	    { return UCmxRXBUF; }
  async command void     Usci.setRxbuf(uint8_t v)   { UCmxRXBUF = v; }
  async command uint8_t  Usci.getTxbuf()	    { return UCmxTXBUF; }
  async command void     Usci.setTxbuf(uint8_t v)   { UCmxTXBUF = v; }
  async command uint8_t  Usci.getAbctl()	    { return UCmxABCTL; }
  async command void     Usci.setAbctl(uint8_t v)   { UCmxABCTL = v; }
  async command uint16_t Usci.getIrctl()	    { return UCmxIRCTL; }
  async command void	 Usci.setIrctl(uint16_t v)  { UCmxIRCTL = v; }
  async command uint8_t	 Usci.getIrtctl()	    { return UCmxIRTCTL; }
  async command void	 Usci.setIrtctl(uint8_t v)  { UCmxIRTCTL = v; }
  async command uint8_t	 Usci.getIrrctl()	    { return UCmxIRRCTL; }
  async command void	 Usci.setIrrctl(uint8_t v)  { UCmxIRRCTL = v; }

  async command uint16_t Usci.getI2Coa()            { return UCmxI2COA; }
  async command void     Usci.setI2Coa(uint16_t v)  { UCmxI2COA = v; }

  async command uint16_t Usci.getI2Csa()            { return UCmxI2CSA; }
  async command void     Usci.setI2Csa(uint16_t v)  { UCmxI2CSA = v; }

  async command uint16_t Usci.getIctl()		    { return UCmxICTL; }
  async command uint16_t Usci.setIctl(uint16_t v)   { UCmxICTL = v; }
  async command uint8_t  Usci.getIe()		    { return UCmxIE; }
  async command void     Usci.setIe(uint8_t v)	    { UCmxIE = v; }
  async command uint8_t  Usci.getIfg()		    { return UCmxIFG; }
  async command void	 Usci.setIfg(uint8_t v)	    { UCmxIFG = v; }

  async command bool	 Usci.isRxIntrPending()	    { return (UCmxIFG & UCRXIFG); }
  async command void	 Usci.clrRxIntr()	    { MSP430_USCI_ATOMIC_LOWLEVEL UCmxIFG &= ~UCRXIFG; }
  async command void	 Usci.disableRxIntr()	    { MSP430_USCI_ATOMIC_LOWLEVEL UCmxIE  &= ~UCRXIE;  }
  async command void	 Usci.enableRxIntr()	    { MSP430_USCI_ATOMIC_LOWLEVEL UCmxIE  |=  UCRXIE;  }

  async command bool	 Usci.isTxIntrPending()	    { return (UCmxIFG & UCTXIFG); }
  async command void	 Usci.clrTxIntr()	    { MSP430_USCI_ATOMIC_LOWLEVEL UCmxIFG &= ~UCTXIFG; }
  async command void	 Usci.disableTxIntr()	    { MSP430_USCI_ATOMIC_LOWLEVEL UCmxIE  &= ~UCTXIE;  }
  async command void	 Usci.enableTxIntr()	    { MSP430_USCI_ATOMIC_LOWLEVEL UCmxIE  |=  UCTXIE;  }

  async command bool	 Usci.isBusy()		    { return (UCmxSTAT & UCBUSY); }

  async command uint8_t  Usci.getIv()		    { return UCmxIV; }


  /* I2C bits
   *
   * set direction of the bus
   */
  async command void Usci.setTransmitMode()	   { MSP430_USCI_ATOMIC_LOWLEVEL UCmxCTL1 |=  UCTR; }
  async command void Usci.setReceiveMode()	   { MSP430_USCI_ATOMIC_LOWLEVEL UCmxCTL1 &= ~UCTR; }
  async command bool Usci.getTransmitReceiveMode() { return (UCmxCTL1 & UCTR); }

  /* NACK, Stop condition, or Start condition, automatically cleared */
  async command void Usci.setTxNack()		   { MSP430_USCI_ATOMIC_LOWLEVEL UCmxCTL1 |= UCTXNACK; }
  async command void Usci.setTxStop()		   { MSP430_USCI_ATOMIC_LOWLEVEL UCmxCTL1 |= UCTXSTP;  }
  async command void Usci.setTxStart()		   { MSP430_USCI_ATOMIC_LOWLEVEL UCmxCTL1 |= UCTXSTT;  }

  async command bool Usci.getTxNack()              { return (UCmxCTL1 & UCTXNACK); }
  async command bool Usci.getTxStop()              { return (UCmxCTL1 & UCTXSTP);  }
  async command bool Usci.getTxStart()             { return (UCmxCTL1 & UCTXSTT);  }

  async command bool Usci.isBusBusy()		   { return (UCmxSTAT & UCBBUSY);  }

  async command bool Usci.isNackIntrPending()	   { return (UCmxIFG & UCNACKIFG); }
  async command void Usci.clrNackIntr()		   { MSP430_USCI_ATOMIC_LOWLEVEL UCmxIFG &= ~UCNACKIFG; }

  /*
   * Caller should disable interrupts.
   */
  async command void Usci.configure (const msp430_usci_config_t* config,
                                     bool leave_in_reset) {
    if (! config) {
      return;				/* panic? */
    }
    UCmxCTL1  = config->ctl1 | UCSWRST;
    UCmxCTL0  = config->ctl0;
    UCmxBR1   = config->br1;
    UCmxBR0   = config->br0;
    UCmxMCTL  = config->mctl;
    UCmxI2COA = config->i2coa;
    if (!leave_in_reset) {
      call Usci.leaveResetMode_();
    }
  }

  async command void Usci.enterResetMode_ () {
#if defined(WITH_IAR)
    UCmxCTL1 |= UCSWRST;
#else
    __asm__ __volatile__("bis %0, %1" : : "i" UCSWRST, "m" UCmxCTL1);
#endif
  }

  async command void Usci.leaveResetMode_ () {
#if defined(WITH_IAR)
    UCmxCTL1 &= ~UCSWRST;
#else
    __asm__ __volatile__("bic %0, %1" : : "i" UCSWRST, "m" UCmxCTL1);
#endif
  }


  async command uint8_t Usci.currentMode () {
    atomic {
      if (! (UCmxCTL0 & UCSYNC)) {
        return MSP430_USCI_UART;
      }
      if (UCMODE_3 == (UCmxCTL0 & (UCMODE0 | UCMODE1))) {
        return MSP430_USCI_I2C;
      }
      return MSP430_USCI_SPI;
    }
  }


  /*
   * Upon receipt of an interrupt, if the USCI is active then demux
   * the interrupt to the handler for the appropriate USCI mode.
   */

  async event void RawInterrupts.interrupted (uint8_t iv) {
    if (call ArbiterInfo.inUse()) {
      signal Interrupts.interrupted[ call Usci.currentMode() ](iv);
    }
  }

  default async event void Interrupts.interrupted[uint8_t mode] (uint8_t iv) { }

#undef UCmxIV
#undef UCmxIFG
#undef UCmxIE
#undef UCmxICTL
#undef UCmxI2CSA
#undef UCmxIRRCTL
#undef UCmxIRTCTL
#undef UCmxIRCTL
#undef UCmxI2COA
#undef UCmxABCTL
#undef UCmxTXBUF
#undef UCmxRXBUF
#undef UCmxSTAT
#undef UCmxMCTL
#undef UCmxBRW
#undef UCmxCTL0
#undef UCmxCTL1
#undef UCmxCTLW0

}
