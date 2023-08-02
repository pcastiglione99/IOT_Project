#include "RadioRoute.h"

configuration RadioRouteAppC {}
implementation {
/****** COMPONENTS *****/
  components MainC, RadioRouteC as App, LedsC;
  components new AMSenderC(AM_RADIO_ROUTE_MSG);
  components new AMReceiverC(AM_RADIO_ROUTE_MSG);
  components new TimerMilliC() as Timer0;
  //components new TimerMilliC() as Timer1;
  components ActiveMessageC;
  
  App.Boot -> MainC.Boot;
  
  App.Receive -> AMReceiverC;
  App.AMSend -> AMSenderC;
  App.AMControl -> ActiveMessageC;
  App.Leds -> LedsC;
  App.Timer0 -> Timer0;
  //App.Timer1 -> Timer1;
  App.Packet -> AMSenderC;

}
