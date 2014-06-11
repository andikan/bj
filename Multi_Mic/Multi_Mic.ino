int s0 = 10;
int s1 = 9;
int s2 = 8;

int mapping[4] = {0, 5, 1, 7};

void setup(){
  Serial.begin(57600);
  
  pinMode(s0, OUTPUT);
  pinMode(s1, OUTPUT);
  pinMode(s2, OUTPUT);
}

void loop(){
  for (int i = 0; i < 4; i++){
    int idx = mapping[i];

    Serial.print('s');
    Serial.print(',');
    Serial.print(i);
    Serial.print('\n');

    digitalWrite(s0, bitRead(idx, 0));
    digitalWrite(s1, bitRead(idx, 1));
    digitalWrite(s2, bitRead(idx, 2));
    
    delay(70);
    
    Serial.print('e');
    Serial.print(',');
    Serial.print(i);
    Serial.print('\n');

    delay(10);
  }
}
