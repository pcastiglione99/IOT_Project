#ifndef RADIO_ROUTE_H
#define RADIO_ROUTE_H

typedef nx_struct CONNECT_msg {
	nx_uint8_t ID;

} CONNECT_msg_t;

typedef nx_struct CONNACK_msg {

} CONNACK_msg_t;

typedef nx_struct SUBSCRIBE_msg {

	nx_uint8_t ID;
	nx_uint8_t topic;

} SUBSCRIBE_msg_t;

typedef nx_struct SUBACK_msg {

} SUBACK_msg_t;

typedef nx_struct PUBLISH_msg {

	nx_uint8_t topic;
	nx_uint16_t payload;

} PUBLISH_msg_t;




enum {
  AM_RADIO_ROUTE_MSG = 10,
};

#endif
