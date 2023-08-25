#include "Timer.h"
#include "mqtt.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "printf.h"

#define N_CLIENTS 8
#define PANC_ID 9

#define CONNECT 0
#define CONNACK 1
#define SUBSCRIBE 2
#define SUBACK 3
#define PUBLISH 4

#define N_TOPICS 3
#define TEMPERATURE 0
#define HUMIDITY 1
#define LUMINOSITY 2


#define DEFAULT_ACK_WAIT 500
#define MAX_SUB_WAIT 5000
#define MAX_PUB_WAIT 10000


module mqttC @safe() {
  uses {
    interface Boot;
    interface Leds;
    interface Receive;
    interface AMSend;
    interface Timer<TMilli> as Timer0;
    interface Timer<TMilli> as Timer_wait_CONNACK;
    interface Timer<TMilli> as Timer_wait_SUBACK;
	interface Timer<TMilli> as Timer_SUB;
	interface Timer<TMilli> as Timer_PUB;
    interface SplitControl as AMControl;
    interface Packet;
	interface Random;
  }
}

implementation {
	typedef struct ack_msg {
		bool status;
		uint32_t seq;
	} Ack_msg;

	typedef struct Panc_table {
		bool connection[N_CLIENTS];
		bool subscription[N_TOPICS][N_CLIENTS];
	} Panc_table;

	message_t packet;
	bool locked;
	uint16_t time_delays[N_CLIENTS]={61,173,267,371,479,583,689,799};
	uint8_t n_subscription_sim[N_CLIENTS] = {2, 1, 1, 1, 1, 3, 2, 1};
	uint8_t subscribed_sim[N_CLIENTS][N_TOPICS];

	Panc_table panc_table;
	uint32_t conn_ack_wait = DEFAULT_ACK_WAIT;
	uint32_t sub_ack_wait = DEFAULT_ACK_WAIT;
	Ack_msg waiting_CONNACK;
	Ack_msg waiting_SUBACK;
	uint8_t queued_sub_topic;
	
	void send_connect_to_PANC();
	void send_subscribe(uint8_t topic);
	void send_publish(uint8_t topic, uint16_t payload);
	void create_connection(uint8_t client_ID, uint32_t seq);
	void create_subscription(uint8_t topic, uint8_t client_ID, uint32_t seq);
	void forward_publish(uint8_t type, uint8_t client_ID, uint8_t topic, uint16_t payload);
	void init_panc_table(Panc_table* table);
	bool isConnected(Panc_table* table, uint8_t ID);
	bool isSubscribed(Panc_table* table, uint8_t topic, uint8_t ID);

    void init_panc_table(Panc_table* table) {
    	uint16_t i;
		uint16_t j;
    	for (i = 0; i < N_CLIENTS; i++) {
      		table->connection[i] = FALSE;
    	}
		for(i = 0; i < N_TOPICS; i++) {
    		for (j = 0; j < N_CLIENTS; j++) {
      			table->subscription[i][j] = FALSE;
    		}
		}
	};

	bool isConnected(Panc_table* table, uint8_t ID) {
    	return table->connection[ID - 1];
	};
	bool isSubscribed(Panc_table* table, uint8_t topic, uint8_t ID) {
    	return table->subscription[topic][ID - 1];
	};
	
	event void Boot.booted() {
		dbg("boot", "APP BOOTED.\n");
    	call AMControl.start();
    	if(TOS_NODE_ID == PANC_ID) {
			init_panc_table(&panc_table);
		}
		waiting_CONNACK.status = FALSE;
		waiting_SUBACK.status = FALSE;
    }

  	event void AMControl.startDone(error_t err) {
    	if (err == SUCCESS) {
    		dbg("radio", "Radio started.\n");
      		if (TOS_NODE_ID != PANC_ID) call Timer0.startOneShot(time_delays[TOS_NODE_ID - 1]);
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
	  		mqtt_msg_t* msg = (mqtt_msg_t*) payload;
	  		if(TOS_NODE_ID == PANC_ID) { //PANC
	  			switch (msg->type){
	  				case CONNECT:
						dbg("radio_rec", "CONNECT received from %d and seq %d.\n", msg->ID, msg->seq);
	  					create_connection(msg->ID, msg->seq);
	  					break;
	  				case SUBSCRIBE:
						dbg("radio_rec", "SUBSCRIBE received from %d with topic %d and seq %d.\n", msg->ID, msg->topic, msg->seq);
	  					create_subscription(msg->topic, msg->ID, msg->seq);
	  					break;
	  				case PUBLISH:
						if (isConnected(&panc_table, msg->ID)){
							dbg("radio_rec", "PUBLISH received from %d on topic:%d with payload:%d.\n", msg->ID, msg->topic, msg->payload);
	  						forward_publish(msg->type, msg->ID, msg->topic, msg->payload);
						}else{
							dbg("radio_rec", "PUBLISH received from not connected node [ID: %d].\n", msg->ID);
						}
	  					break;
	  				default:
	  					dbgerror("radio_rec", "INVALID MESSAGE.\n");
	  					return;
	  				
	  			}
	  		} else { //CLIENT
	  			switch (msg->type){
	  				case CONNACK:
	  					dbg("radio_rec", "CONNACK received with seq %d.\n", msg->seq);
						if (waiting_CONNACK.status == TRUE && waiting_CONNACK.seq == msg->seq){
							dbg("general", "Connected to PANC.\n");
							waiting_CONNACK.status = FALSE;
							waiting_CONNACK.seq = 0;
							conn_ack_wait = DEFAULT_ACK_WAIT;
							call Timer_SUB.startOneShotAt((call Random.rand32() % MAX_SUB_WAIT), 500);
							call Timer_PUB.startPeriodicAt((call Random.rand32() % MAX_PUB_WAIT), 500);
						}
	  					break;
	  				case SUBACK:
	  					dbg("radio_rec", "SUBACK received with seq %d.\n", msg->seq);
						if (waiting_SUBACK.status == TRUE && waiting_SUBACK.seq == msg->seq){
							dbg("general", "Subscribed to a topic %d.\n", msg->topic);
							waiting_SUBACK.status = FALSE;
							waiting_SUBACK.seq = 0;
							sub_ack_wait = DEFAULT_ACK_WAIT;
							subscribed_sim[TOS_NODE_ID - 1][msg->topic] = 1;
							n_subscription_sim[TOS_NODE_ID - 1]--;
							if (n_subscription_sim[TOS_NODE_ID - 1] > 0){
								call Timer_SUB.startOneShotAt((call Random.rand32() % MAX_SUB_WAIT), 500);								 
							}
						}
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
	

	void send_connect_to_PANC() {
		uint32_t seq;
		mqtt_msg_t* connect_msg;
	
		connect_msg = (mqtt_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_msg_t));
		if (connect_msg == NULL) {
			return;
		}
		connect_msg->type = CONNECT;
		connect_msg->ID = TOS_NODE_ID;
		connect_msg->seq = call Random.rand32(); 

		if (call AMSend.send(PANC_ID, &packet, sizeof(mqtt_msg_t)) == SUCCESS) {
			dbg("radio_send", "Send CONNECT packet\n");
			locked = TRUE;
			waiting_CONNACK.status = TRUE;
			waiting_CONNACK.seq = connect_msg->seq;
			call Timer_wait_CONNACK.startOneShot(conn_ack_wait);
		}
	}	
	event void Timer_wait_CONNACK.fired() {
		if(waiting_CONNACK.status){
			conn_ack_wait *= 2;
			send_connect_to_PANC();
		}
	}
	
	
	
	void create_connection(uint8_t client_ID, uint32_t seq) {
		
		mqtt_msg_t* CONNACK_msg;
		
		dbg("general", "Creating connection with client %d and seq %d.\n",client_ID, seq);
		panc_table.connection[client_ID - 1] = TRUE;
		
		
		CONNACK_msg = (mqtt_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_msg_t));
		if (CONNACK_msg == NULL) {
			return;
		}
		CONNACK_msg->type = CONNACK;
		CONNACK_msg->ID = TOS_NODE_ID;
		CONNACK_msg->seq = seq;

		if (call AMSend.send(client_ID, &packet, sizeof(mqtt_msg_t)) == SUCCESS) {
			dbg("radio_send", "Send CONNACK packet to %d.\n", client_ID);
			locked = TRUE;
		}

	}
	
	void create_subscription(uint8_t topic, uint8_t client_ID, uint32_t seq) {
			
		mqtt_msg_t* SUBACK_msg;
		
		dbg("general", "Creating subscription with client %d and topic %d.\n",client_ID, topic);
		panc_table.subscription[topic][client_ID - 1] = TRUE;
		
		SUBACK_msg = (mqtt_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_msg_t));
		if (SUBACK_msg == NULL) {
			return;
		}
		SUBACK_msg->type = SUBACK;
		SUBACK_msg->ID = TOS_NODE_ID;
		SUBACK_msg->seq = seq;
		SUBACK_msg->topic = topic;
		
		if (call AMSend.send(client_ID, &packet, sizeof(mqtt_msg_t)) == SUCCESS) {
			dbg("radio_send", "Send SUBACK packet to %d.\n", client_ID);
			locked = TRUE;
		}
		
		
	}
	
	event void Timer_wait_SUBACK.fired() {
		if(waiting_SUBACK.status) {
			sub_ack_wait *= 2;
			send_subscribe(queued_sub_topic);
		}
	}

	event void Timer_SUB.fired() {
		uint16_t new_topic = call Random.rand32() % N_TOPICS;
		uint8_t dir = (call Random.rand32() % 2);
		while (subscribed_sim[TOS_NODE_ID - 1][new_topic] == 1){
			if (new_topic == 0 && dir == 0){
				dir = 1;
			}
			new_topic += (dir == 0) ? -1 : 1;
		}
		send_subscribe(new_topic);
	}

	event void Timer_PUB.fired() {
		send_publish(call Random.rand32() % N_TOPICS, call Random.rand32() % 100);
	}
	
	void send_subscribe(uint8_t topic) {
		mqtt_msg_t* SUBSCRIBE_msg;
		
		queued_sub_topic = topic;
	

		SUBSCRIBE_msg = (mqtt_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_msg_t));
		if (SUBSCRIBE_msg == NULL) {
			return;
		}
		SUBSCRIBE_msg->type = SUBSCRIBE;
		SUBSCRIBE_msg->ID = TOS_NODE_ID;
		SUBSCRIBE_msg->topic = topic;
		SUBSCRIBE_msg->seq = call Random.rand32(); 
		
		if (call AMSend.send(PANC_ID, &packet, sizeof(mqtt_msg_t)) == SUCCESS) {
			dbg("radio_send", "Send SUBSCRIBE packet\n");
			locked = TRUE;
			waiting_SUBACK.status = TRUE;
			waiting_SUBACK.seq = SUBSCRIBE_msg->seq;
			call Timer_wait_SUBACK.startOneShot(sub_ack_wait);
		}
	}
	
	void send_publish(uint8_t topic, uint16_t payload) {
		mqtt_msg_t* PUBLISH_msg;
		
		PUBLISH_msg = (mqtt_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_msg_t));
		if (PUBLISH_msg == NULL) {
			return;
		}
		PUBLISH_msg->type = PUBLISH;
		PUBLISH_msg->ID = TOS_NODE_ID;
		PUBLISH_msg->topic = topic;
		PUBLISH_msg->payload = payload;
		
		if (call AMSend.send(PANC_ID, &packet, sizeof(mqtt_msg_t)) == SUCCESS) {
			dbg("radio_send", "Send PUBLISH packet\n");
			locked = TRUE;
		}
	}
	
	void forward_publish(uint8_t type, uint8_t ID, uint8_t topic, uint16_t payload) {
		uint8_t i;
		
		mqtt_msg_t* PUBLISH_msg;
		
		PUBLISH_msg = (mqtt_msg_t*)call Packet.getPayload(&packet, sizeof(mqtt_msg_t));
		if (PUBLISH_msg == NULL) {
			return;
		}
		PUBLISH_msg->type = type;
		PUBLISH_msg->ID = PANC_ID;
		PUBLISH_msg->topic = topic;
		PUBLISH_msg->payload = payload;
		// printf("%d,%d\n",topic,payload);      
  	    // printfflush();
		
		for(i = 1; i <= N_CLIENTS; i++) {
			if(isSubscribed(&panc_table, topic, i)) {
				if (call AMSend.send(i , &packet, sizeof(mqtt_msg_t)) == SUCCESS) {
					dbg("radio_send", "Send PUBLISH packet to %d.\n",i);
					locked = TRUE;
				}
			}
		}
	 }
	
	
	
}

