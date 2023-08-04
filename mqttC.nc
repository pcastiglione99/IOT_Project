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

#define TEMPERATURE 0
#define HUMIDITY 1
#define LUMINOSITY 2

#define ACK_WAIT 500


module mqttC @safe() {
  uses {
    interface Boot;
    interface Leds;
    interface Receive;
    interface AMSend;
    interface Timer<TMilli> as Timer0;
    interface Timer<TMilli> as Timer_wait_CONNACK;
    interface Timer<TMilli> as Timer_wait_SUBACK;
    interface Timer<TMilli> as Timer_TEST_SUB;
    interface Timer<TMilli> as Timer_TEST_PUB;
    interface SplitControl as AMControl;
    interface Packet;
  }
}

implementation {
	message_t packet;
	bool locked;
	uint16_t time_delays[N_CLIENTS]={61,173,267,371,479,583,689,799};
	bool connection[MAX_CONNECTION];
	bool subscription[3][MAX_CONNECTION];


	bool CONNACK_received = FALSE;
	bool SUBACK_received = FALSE;
	uint8_t queued_topic;
	bool wait_for_ACK = FALSE;
	
	void send_connect_to_PANC();
	void send_subscribe(uint8_t topic);
	void send_publish(uint8_t topic, uint16_t payload);
	
	
	void create_connection(uint8_t client_ID);
	void create_subscription(uint8_t client_ID, uint8_t topic);
	void forward_publish(uint8_t type, uint8_t client_ID, uint8_t topic, uint16_t payload);
	
	
	    
    void init_connect() {
    	uint16_t i;
    	for (i = 1; i < MAX_CONNECTION; i++) {
      		connection[i] = FALSE;
    	}
		connection[0]=TRUE;
	};
	
    void init_subscription(){
    	uint16_t i;
    	uint16_t j;
    	for(i = 0; i < 3; i++) {
    		for (j = 0; j < MAX_CONNECTION; j++) {
      			subscription[i][j] = FALSE;
    		}
		}
	};
	
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
	  					dbg("radio_rec", "CONNECT received from %d.\n", msg->client_ID);
	  					create_connection(msg->client_ID);
	  					break;
	  				case SUBSCRIBE:
	  					dbg("radio_rec", "SUBSCRIBE received from %d to topic %d.\n", msg->client_ID, msg->topic);
	  					if(connection[msg->client_ID]) {
	  						(!subscription[msg->topic][msg->client_ID]) ? create_subscription(msg->topic, msg->client_ID) : dbg("general", "Already subscribed!!!!.\n"); ;
	  					}
	  					break;
	  				case PUBLISH:
	  					dbg("radio_rec", "PUBLISH received from %d on topic:%d with payload:%d.\n", msg->client_ID, msg->topic, msg->payload);
	  					forward_publish(msg->type, msg->client_ID, msg->topic, msg->payload);
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
	  					dbg("general", "Connected to PANC.\n");
	  					if (TOS_NODE_ID == 3) call Timer_TEST_SUB.startOneShot(1000); // To test subscription
	  					if (TOS_NODE_ID == 1) call Timer_TEST_PUB.startOneShot(2000);
	  					break;
	  				case SUBACK:
	  					SUBACK_received = TRUE;
	  					dbg("radio_rec", "SUBACK received.\n");
	  					break;
	  				case PUBLISH:
	  					dbg("radio_rec", "PUBLISH received on TOPIC:%d VALUE:%d.\n", msg->topic, msg->payload);
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
		send_connect_to_PANC();
	}
	
	event void Timer_TEST_SUB.fired() {
		send_subscribe(HUMIDITY);
	}
	
	event void Timer_TEST_PUB.fired() {
		send_publish(HUMIDITY, 300);
	}
	
	void send_connect_to_PANC() {
	
		mqtt_msg_t* connect_msg;

		connect_msg = (mqtt_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_msg_t));
		if (connect_msg == NULL) {
			return;
		}
		connect_msg->type = CONNECT;
		connect_msg->client_ID = TOS_NODE_ID;
		
		if (call AMSend.send(PANC_ID, &packet, sizeof(mqtt_msg_t)) == SUCCESS) {
			dbg("radio_send", "Send CONNECT packet\n");
			locked = TRUE;
			wait_for_ACK = TRUE;
			call Timer_wait_CONNACK.startOneShot(ACK_WAIT);
		}
	}	
	event void Timer_wait_CONNACK.fired() {
		if(!CONNACK_received) send_connect_to_PANC();
	}
	
	
	
	void create_connection(uint8_t client_ID) {
		
		mqtt_msg_t* CONNACK_msg;
		
		dbg("general", "Creating connection with client %d.\n",client_ID);
		connection[client_ID] = TRUE;
		
		
		CONNACK_msg = (mqtt_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_msg_t));
		if (CONNACK_msg == NULL) {
			return;
		}
		CONNACK_msg->type = CONNACK;
		
		if (call AMSend.send(client_ID, &packet, sizeof(mqtt_msg_t)) == SUCCESS) {
			dbg("radio_send", "Send CONNACK packet to %d.\n", client_ID);
			locked = TRUE;
		}

	}
	
	void create_subscription(uint8_t topic, uint8_t client_ID) {
			
		mqtt_msg_t* SUBACK_msg;
		
		dbg("general", "Creating subscription to topic %d.\n",topic);
		subscription[topic][client_ID] = TRUE;
		
		SUBACK_msg = (mqtt_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_msg_t));
		if (SUBACK_msg == NULL) {
			return;
		}
		SUBACK_msg->type = SUBACK;
		
		if (call AMSend.send(client_ID, &packet, sizeof(mqtt_msg_t)) == SUCCESS) {
			dbg("radio_send", "Send SUBACK packet to %d.\n", client_ID);
			locked = TRUE;
		}
		
		
	}
	

	void send_subscribe(uint8_t topic) {
		mqtt_msg_t* SUBSCRIBE_msg;
		
		queued_topic = topic;
	

		SUBSCRIBE_msg = (mqtt_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_msg_t));
		if (SUBSCRIBE_msg == NULL) {
			return;
		}
		SUBSCRIBE_msg->type = SUBSCRIBE;
		SUBSCRIBE_msg->client_ID = TOS_NODE_ID;
		SUBSCRIBE_msg->topic = topic;
		
		if (call AMSend.send(PANC_ID, &packet, sizeof(mqtt_msg_t)) == SUCCESS) {
			dbg("radio_send", "Send SUBSCRIBE packet\n");
			locked = TRUE;
			wait_for_ACK = TRUE;
			call Timer_wait_SUBACK.startOneShot(ACK_WAIT);
		}
	}	
	event void Timer_wait_SUBACK.fired() {
		if(!SUBACK_received) send_subscribe(queued_topic);
	}
	
	
	void send_publish(uint8_t topic, uint16_t payload) {
		mqtt_msg_t* PUBLISH_msg;
		
		PUBLISH_msg = (mqtt_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_msg_t));
		if (PUBLISH_msg == NULL) {
			return;
		}
		PUBLISH_msg->type = PUBLISH;
		PUBLISH_msg->client_ID = TOS_NODE_ID;
		PUBLISH_msg->topic = topic;
		PUBLISH_msg->payload = payload;
		
		if (call AMSend.send(PANC_ID, &packet, sizeof(mqtt_msg_t)) == SUCCESS) {
			dbg("radio_send", "Send PUBLISH packet\n");
			locked = TRUE;
		}
	}
	
	void forward_publish(uint8_t type, uint8_t client_ID, uint8_t topic, uint16_t payload) {
		uint8_t i;
		
		mqtt_msg_t* PUBLISH_msg;
		
		PUBLISH_msg = (mqtt_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_msg_t));
		if (PUBLISH_msg == NULL) {
			return;
		}
		PUBLISH_msg->type = type;
		PUBLISH_msg->client_ID = client_ID;
		PUBLISH_msg->topic = topic;
		PUBLISH_msg->payload = payload;
		
		for(i = 1; i < MAX_CONNECTION; i++) {
			if(subscription[topic][i]) {
				if (call AMSend.send(i, &packet, sizeof(mqtt_msg_t)) == SUCCESS) {
				dbg("radio_send", "Send PUBLISH packet to %d.\n",i);
				locked = TRUE;
				}
			}
		}
	 }
	
	
	
}

