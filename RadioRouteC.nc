#include "Timer.h"
#include "RadioRoute.h"


module RadioRouteC @safe() {
  uses {
    interface Boot;
    interface Leds;
    interface Receive;
    interface AMSend;
    interface Timer<TMilli> as Timer0;
    //interface Timer<TMilli> as Timer1;
    interface SplitControl as AMControl;
    interface Packet;
  }
}

implementation {
	message_t packet;
	bool locked;
	uint16_t time_delays[8]={61,173,267,371,479,583,689,799};
	
	void send(uint16_t address, message_t* packet);
	void connect_to_PAN();
	
	event void Boot.booted() {
		dbg("boot", "APP BOOTED.\n");
    	call AMControl.start();
    	
    }

  	event void AMControl.startDone(error_t err) {
    	if (err == SUCCESS) {
    		dbg("radio", "Radio started.\n");
      		if (TOS_NODE_ID != 0) {
      			call Timer0.startOneShot( time_delays[TOS_NODE_ID - 1] );
      		}
    	}
    	else {
      		call AMControl.start();
    	}
  	}

  	event void AMControl.stopDone(error_t err) { 
  		// do nothing
	}

  	event void AMSend.sendDone(message_t* bufPtr, error_t error) {
    	if (&packet == bufPtr) {
      		locked = FALSE;
    	}
	}
	

  event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
    if (len != sizeof(mqtt_msg_t)) {return bufPtr;}
    else {
      mqtt_msg_t* msg = (mqtt_msg_t*)payload;
      
      if(TOS_NODE_ID == 0) {
      
      	switch (msg->type){
      		case 0: //CONNECT
      			dbg("radio_rec", "Connect received from %d.\n", msg->ID);
      	}
      }
      
      return bufPtr;
    }
  }
	
	
	 
	event void Timer0.fired() {
		connect_to_PAN();
	}
	
	void connect_to_PAN() {
	
		mqtt_msg_t* connect_msg ;

		connect_msg = (mqtt_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_msg_t));
		if (connect_msg == NULL) {
			return;
		}
		connect_msg->ID = TOS_NODE_ID;
		if (call AMSend.send(0, &packet, sizeof(mqtt_msg_t)) == SUCCESS) {
			dbg("radio_send", "Send connection packet\n");
			locked = TRUE;
		}
	}
}
