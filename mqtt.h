 #ifndef MQTT_H
#define MQTT_H

/*
Type:
CONNECT 0
CONNACK 1
SUBSCRIBE 2
SUBACK 3
PUBLISH 4
*/

typedef nx_struct mqtt_msg {
	nx_uint8_t type;
	nx_uint8_t client_ID;
	nx_uint8_t topic;
	nx_uint16_t payload;
	nx_uint32_t seq;
} mqtt_msg_t;

enum {
  AM_MQTT_MSG = 10,
};

#endif
