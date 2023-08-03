#include "Timer.h"
#include "mqtt.h"

#define N_CLIENTS 8
#define PANC_ID 0
#define MAX_CONNECTION 16

#define CONNECT 0
#define CONNACK 1
#define SUBSCRIBE 2
#define SUBACK 3
#define PUBLISH 4

#define CONNACK_WAIT 500


module mqttC @safe() {
  uses {
    interface Boot;
    interface Leds;
    interface Receive;
    interface AMSend;
    interface Timer<TMilli> as Timer0;
    interface Timer<TMilli> as Timer_wait_connack;
    interface SplitControl as AMControl;
    interface Packet;
  }
}

implementation {
	message_t packet;
	bool locked;
	uint16_t time_delays[N_CLIENTS]={61,173,267,371,479,583,689,799};
	bool connection[MAX_CONNECTION];
    
    void init_connect(){
    
    	uint16_t i;
    	for (i = 1; i < MAX_CONNECTION; i++) {
      		connection[i] = FALSE;
    	}
		connection[0]=TRUE;
	};
	
	bool CONNECT_sent = FALSE;
	bool CONNACK_received = FALSE;
	
	void connect_to_PANC();
	void create_connection(nx_uint8_t client_ID);
	
	event void Boot.booted() {
		dbg("boot", "APP BOOTED.\n");
    	call AMControl.start();
    	if(TOS_NODE_ID == PANC_ID) init_connect();
    	
    }

  	event void AMControl.startDone(error_t err) {
    	if (err == SUCCESS) {
    		dbg("radio", "Radio started.\n");
      		if (TOS_NODE_ID != PANC_ID) call Timer0.startOneShot( time_delays[TOS_NODE_ID - 1] );
    	}
    	else call AMControl.start();
  	}

  	event void AMControl.stopDone(error_t err) { /* do nothing */ }

  	event void AMSend.sendDone(message_t* bufPtr, error_t error) {
    	if (&packet == bufPtr) locked = FALSE;
	}
	

	event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
		if (len != sizeof(mqtt_msg_t)) {return bufPtr;}
		else {
	  		mqtt_msg_t* msg = (mqtt_msg_t*)payload;
	  
	  		if(TOS_NODE_ID == PANC_ID) { //PANC
	  
	  			switch (msg->type){
	  				case CONNECT:
	  					dbg("radio_rec", "CONNECT received from %d.\n", msg->ID);
	  					create_connection(msg->ID);
	  					break;
	  				case SUBSCRIBE:
	  					break;
	  				case PUBLISH:
	  					break;
	  				default:
	  					dbgerror("radio_rec", "INVALID MESSAGE.\n");
	  					return;
	  				
	  			}
	  		} else { //CLIENT
	  			switch (msg->type){
	  				case CONNACK:
	  					CONNACK_received = TRUE;
	  					dbg("radio_rec", "CONNACK received.\n");
	  					break;
	  				case SUBACK:
	  					break;
	  				case PUBLISH:
	  					break;
	  				default:
	  					dbgerror("radio_rec", "INVALID MESSAGE.\n");
	  					return;
	  			}
	  		}
	  		
	  
	  		return bufPtr;
		}
	}

	
	 
	event void Timer0.fired() {
		connect_to_PANC();
	}
	
	
	void connect_to_PANC() {
	
		mqtt_msg_t* connect_msg;

		connect_msg = (mqtt_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_msg_t));
		if (connect_msg == NULL) {
			return;
		}
		connect_msg->type = CONNECT;
		connect_msg->ID = TOS_NODE_ID;
		
		if (call AMSend.send(PANC_ID, &packet, sizeof(mqtt_msg_t)) == SUCCESS) {
			dbg("radio_send", "Send CONNECTION packet\n");
			locked = TRUE;
			CONNECT_sent = TRUE;
			call Timer_wait_connack.startOneShot(CONNACK_WAIT);
		}
	}
	
	event void Timer_wait_connack.fired() {
		if(!CONNACK_received) connect_to_PANC();
		
	}
	
	void create_connection(nx_uint8_t client_ID) {
	
		mqtt_msg_t* connack_msg;
	
		if(!connection[client_ID]){
		
			connection[client_ID] = TRUE;

			connack_msg = (mqtt_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_msg_t));
			if (connack_msg == NULL) {
				return;
			}
			connack_msg->type = CONNACK;
		
			if (call AMSend.send(client_ID, &packet, sizeof(mqtt_msg_t)) == SUCCESS) {
				dbg("radio_send", "Send CONNACK packet to %d.\n", client_ID);
				locked = TRUE;
			}
		}
	}
	
	
	
}

