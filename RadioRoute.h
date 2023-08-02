#ifndef RADIO_ROUTE_H
#define RADIO_ROUTE_H

/*
Type:
0 CONNECT
1 CONNACK
2 SUBSCRIBE
3 SUBACK
4 PUBLISH
*/

typedef nx_struct mqtt_msg {
	nx_uint8_t type;
	nx_uint8_t ID;
	nx_uint8_t topic;
	nx_uint8_t payload;
} mqtt_msg_t;

enum {
  AM_RADIO_ROUTE_MSG = 10,
};

#endif
