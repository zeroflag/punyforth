# MQTT for PunyForth

* MQTT.forth allows the 8266 to publish messages onto a MQTT message queue using PunyForth
* So far, only pub has been implemented (no sub yet)

# Instructions  
Edit the configuration section in the mqtt.forth file. Specifically, enter the ip address of your mqtt broker. Then upload mqtt.forth to your 8266 board. Publish a message using
```
"topic" "message" mqtt_pub
```
If you do not have a broker to test with then install mosquitto.
```
sudo apt-get install mosquitto mosquitto-clients
```
The broker will run automatically but to see broker diagnostics messages use something like
```
sudo /etc/init.d/mosquitto stop
hostname -I
mosquitto -v
```
and subscribe to a topic using
```
mosquitto_sub -h YOUR_IP_ADDRESS -t "YOUR_TOPIC" -d
```
If everything is working then you will see the published messages in your subscriber terminal.
# Contact

Contact dfoderick@gmail.com  
Dave Foderick  

