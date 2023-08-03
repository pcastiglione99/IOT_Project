#include "mqtt.h"

configuration mqttAppC {}
implementation {
/****** COMPONENTS *****/
  components MainC, mqttC as App, LedsC;
  components new AMSenderC(AM_MQTT_MSG);
  components new AMReceiverC(AM_MQTT_MSG);
  components new TimerMilliC() as Timer0;
  components new TimerMilliC() as Timer_wait_CONNACK;
  components new TimerMilliC() as Timer_wait_SUBACK;
  components ActiveMessageC;
  
  App.Boot -> MainC.Boot;
  
  App.Receive -> AMReceiverC;
  App.AMSend -> AMSenderC;
  App.AMControl -> ActiveMessageC;
  App.Leds -> LedsC;
  App.Timer0 -> Timer0;
  App.Timer_wait_CONNACK -> Timer_wait_CONNACK;
  App.Timer_wait_SUBACK -> Timer_wait_SUBACK;
  App.Packet -> AMSenderC;

}
