#include "mqtt.h"
#include "printf.h"

#define NEW_PRINTF_SEMANTICS

configuration mqttAppC {}
implementation {
/****** COMPONENTS *****/
  components MainC, mqttC as App, LedsC;
  components new AMSenderC(AM_MQTT_MSG);
  components new AMReceiverC(AM_MQTT_MSG);
  components new TimerMilliC() as Timer0;
  components new TimerMilliC() as Timer_wait_CONNACK;
  components new TimerMilliC() as Timer_wait_SUBACK;
  components new TimerMilliC() as Timer_SUB;
  components new TimerMilliC() as Timer_PUB;

  components ActiveMessageC;
  components RandomC;
  // components SerialPrintfC;
  // components SerialStartC;
  
  App.Boot -> MainC.Boot;
  App.Receive -> AMReceiverC;
  App.AMSend -> AMSenderC;
  App.AMControl -> ActiveMessageC;
  App.Leds -> LedsC;
  App.Timer0 -> Timer0;
  App.Timer_wait_CONNACK -> Timer_wait_CONNACK;
  App.Timer_wait_SUBACK -> Timer_wait_SUBACK;
  App.Timer_SUB -> Timer_SUB;
  App.Timer_PUB -> Timer_PUB;
  App.Packet -> AMSenderC;
  App.Random -> RandomC;
  
}
