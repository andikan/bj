/**
  * LiveSpectrum
  *
  * Run an FFT on live line-in input, and plot the spectrum in dB.
  * It has a kind of decaying peak-hold as well.
  * '+' key moves the scale up (increases gain), '-' to move it down.
  * Based on http://processing.org/learning/libraries/forwardfft.html by ddf.
  *
  * 2010-01-22 Dan Ellis dpwe@ee.columbia.edu
  */
import processing.serial.*;
import ddf.minim.analysis.*;
import ddf.minim.*;

Serial serialPort;
String inputString = null;
int lf = 10;    // Linefeed in ASCII

Serial bluetoothSerialPort;

int MIC_NUM = 4;
Minim minim;
AudioInput in;
FFT fft;
float[][] peaks;
float[][] dataBuffers;
int currentChannel = 0;
boolean dataMode = false;

int peak_hold_time = 10;  // how long before peak decays
int[][] peak_age;  // tracks how long peak has been stable, before decaying

// how wide each 'peak' band is, in fft bins
int binsperband = 10;
int peaksize; // how many individual peak bands we have (dep. binsperband)
float gain = 0; // in dB
float dB_scale = 2.0;  // pixels per dB

int buffer_size = 1024;  // also sets FFT size (frequency resolution)
float sample_rate = 44100;

int spectrum_height = 400; // determines range of dB shown
int legend_height = 20;
int spectrum_width = 512; // determines how much of spectrum we see
int legend_width = 40;
int devide_space = 50;

// sensing data
float[] averagePeaks;
float[] activeChannels;
IntList channelWindow;
int activeThreshold = 18;
int directionTime;
int directionThresholdTime = 500;
int swipeTime;
int swipeThresholdTime = 1000;

void setup()
{
  size((legend_width+spectrum_width)*2+devide_space, (spectrum_height+legend_height)*2+devide_space, P2D);
  textMode(SCREEN);
  textFont(createFont("Gill Sans", 12));
 
  minim = new Minim(this);
 
  in = minim.getLineIn(Minim.MONO,buffer_size,sample_rate);
 
  // create an FFT object that has a time-domain buffer 
  // the same size as line-in's sample buffer
  fft = new FFT(in.bufferSize(), in.sampleRate());
  // Tapered window important for log-domain display
  fft.window(FFT.HAMMING);

  // initialize peak-hold structures
  peaksize = 1+Math.round(fft.specSize()/binsperband);
  peaks = new float[MIC_NUM][peaksize];
  peak_age = new int[MIC_NUM][peaksize];

  // initialize data buffers for multiple microphones
  dataBuffers = new float[MIC_NUM][in.bufferSize()];

  // sensing data
  averagePeaks = new float[MIC_NUM];
  activeChannels = new float[MIC_NUM];
  channelWindow = new IntList();

  // read data from arduino
  serialPort = new Serial(this, "/dev/tty.usbmodem1421", 57600);
  serialPort.clear();
  inputString = serialPort.readStringUntil(lf);
  inputString = null;

  bluetoothSerialPort = new Serial(this, "/dev/tty.Bluetooth-Serial-1", 57600);

  // timer
  directionTime = millis();
  swipeTime = millis();
}


void draw()
{
  // clear window
  background(0);

  while (serialPort.available() > 0) {
    inputString = serialPort.readStringUntil('\n');
    if (inputString != null){
      String[] inStringArray = inputString.split(",");
      if(inStringArray.length == 2){
        String actionCode = inStringArray[0];
        int channel = Integer.valueOf(inStringArray[1].substring(0, inStringArray[1].length()-1));

        if(actionCode.equals("s")){
          // println("action: ", actionCode);
          dataMode = false;
          currentChannel = channel;
        }
        else if(actionCode.equals("e")){
          // println("action: ", actionCode);
          dataMode = true;
          currentChannel = channel;
        }
      }
    }
  }

  // draw text
  drawTextInfo();

  // get data
  if(dataMode) {
    // println("current channel: ", currentChannel);
    getDataFromAudioInout(currentChannel);
  }

  for(int micNum = 0; micNum < MIC_NUM; micNum++) {
    // perform a forward FFT on the samples in input buffer
    fft.forward(dataBuffers[micNum]);
    // draw average peak
    drawAveragePeak(micNum);
    // draw peak bars
    drawPeakBars(micNum);
    // draw spectrum
    drawSpectrum(micNum);
    // draw axis
    drawFrequencyAxis(micNum);
    drawLevelAxis(micNum);
  }

  activeChannels = new float[] {-1, -1, -1, -1};
  // collect sensing info
  for(int micNum = 0; micNum < MIC_NUM; micNum++) {
    if(averagePeaks[micNum] > activeThreshold) {
      activeChannels[micNum] = averagePeaks[micNum];
    }
  }

  int activeNum = activeChannelCount();
  if(activeNum > 0){
    if(activeNum == 1) { // four direction
      int activeChannel = 0;
      if(activeChannels[0] > -1){
        activeChannel = 0;
      }
      if(activeChannels[1] > -1){
        activeChannel = 1;
      }
      if(activeChannels[2] > -1){
        activeChannel = 2;
      }
      if(activeChannels[3] > -1){
        activeChannel = 3;
      }

      int passedTime = millis() - directionTime;
      if(passedTime > directionThresholdTime) {
        switch (activeChannel) {
          case 0:
            bluetoothSerialPort.write("up");
            break;
          case 1:
            bluetoothSerialPort.write("right");
            break;
          case 2:
            bluetoothSerialPort.write("left");
            break;
          case 3:
            bluetoothSerialPort.write("down");
            break;
          default:
            break;
        }
        directionTime = millis();
      }

      channelWindow.append(activeChannel);
      if(channelWindow.size() == 1) {
        swipeTime = millis();
      }
      else if(channelWindow.size() == 2 ) {
        if(channelWindow.get(0) != channelWindow.get(1)) {

          if(channelWindow.get(0) == 0 && channelWindow.get(1) == 2) {
            bluetoothSerialPort.write("swipe_down");
          }
          else if(channelWindow.get(0) == 2 && channelWindow.get(1) == 0) {
            bluetoothSerialPort.write("swipe_up");
          }
          else if(channelWindow.get(0) == 2 && channelWindow.get(1) == 3) {
            bluetoothSerialPort.write("swipe_right");
          }
          else if(channelWindow.get(0) == 3 && channelWindow.get(1) == 2) {
            bluetoothSerialPort.write("swipe_left");
          }
          println("window: ", channelWindow);
        }
        channelWindow.clear();
      }
    }
    else if(activeNum == 2) {
      // println("active num: ", 2);
    }
  }
}

int activeChannelCount() {
  int count = 0;
  for(int micNum = 0; micNum < MIC_NUM; micNum++) {
    if(activeChannels[micNum] > -1) {
      count = count + 1;
    }
  }
  return count;
}

void getDataFromAudioInout(int channel){
  for(int i = 0; i < in.bufferSize(); i++){
    dataBuffers[channel][i] = in.mix.get(i);
  }
}

float averagePeak()
{
  float averageValue = 0;
  for(int i = 0; i < peaksize; ++i) {
    averageValue = averageValue + peaks[0][i];
  }
  averageValue = (averageValue == 0) ? 0 : averageValue/peaksize;
  return averageValue;
}

void keyReleased()
{
  // +/- used to adjust gain on the fly
  if (key == '+' || key == '=') {
    gain = gain + 5.0;
  } else if (key == '-' || key == '_') {
    gain = gain - 5.0;
  }

  if(key == '0') {
    bluetoothSerialPort.write("up");0
  }
}
 
void stop()
{
  // always close Minim audio classes when you finish with them
  in.close();
  minim.stop();
 
  super.stop();
}

void drawTextInfo()
{
  text("Mic # 1", legend_width, legend_height); // add text label
  text("Mic # 2", legend_width+spectrum_width+devide_space, legend_height); // add text label
  text("Mic # 3", legend_width, legend_height+devide_space+spectrum_height); // add text label
  text("Mic # 4", legend_width+spectrum_width+devide_space, legend_height+devide_space+spectrum_height); // add text label
}

void drawPeakCurve(int channel)
{
  // draw peak curve
  beginShape();
  curveVertex(legend_width, spectrum_height);
  for(int i = 0; i < peaksize; ++i) {
    // mic 1
    int thisy = spectrum_height - Math.round(peaks[0][i])-5;
    curveVertex(legend_width+binsperband*i+binsperband/2, thisy);
  }
  endShape();
}

void drawAveragePeak(int channel)
{
  float averageValue = 0;
  int activeNum = 0;
  for(int i = 0; i < peaksize; ++i) {
    // if(peaks[channel][i] > 0) {
      averageValue = averageValue + peaks[channel][i];
      activeNum = activeNum + 1;
    // }
  }
  averageValue = (averageValue == 0) ? 0 : averageValue/activeNum;
  averagePeaks[channel] = averageValue;

  pushStyle();
  textSize(26);
  stroke(244, 208, 63);
  if(channel == 0){
    int thisy = spectrum_height - Math.round(averageValue);
    line(legend_width, thisy, legend_width+spectrum_width, thisy);
    text(averageValue, legend_width+100, legend_height);
  }
  else if(channel == 1){
    int thisy = spectrum_height - Math.round(averageValue);
    line(legend_width+spectrum_width+devide_space, thisy, legend_width+spectrum_width+devide_space+spectrum_width, thisy);
    text(averageValue, legend_width+spectrum_width+devide_space+100, legend_height); // add text label
  }
  else if(channel == 2){
    int thisy = 2*spectrum_height+devide_space - Math.round(averageValue);
    line(legend_width, thisy, legend_width+spectrum_width, thisy);
    text(averageValue, legend_width+100, legend_height+spectrum_height+devide_space);
  }
  else if(channel == 3){
    int thisy = 2*spectrum_height+devide_space - Math.round(averageValue);
    line(legend_width+spectrum_width+devide_space, thisy, legend_width+spectrum_width+devide_space+spectrum_width, thisy);
    text(averageValue, legend_width+spectrum_width+devide_space+100, legend_height+spectrum_height+devide_space);
  }
  popStyle();
}

void drawPeakBars(int channel)
{
  // draw peak bars
  noStroke();
  fill(82, 179, 217); // dim cyan
  for(int i = 0; i < peaksize; ++i) { 
    int thisy = spectrum_height - Math.round(peaks[channel][i]);

    if(channel == 0)
      rect(legend_width+binsperband*i, thisy, binsperband, spectrum_height-thisy);
    else if(channel == 1)
      rect(legend_width+spectrum_width+devide_space+binsperband*i, thisy, binsperband, spectrum_height-thisy);
    else if(channel == 2)
      rect(legend_width+binsperband*i, thisy+spectrum_height+devide_space, binsperband, spectrum_height-thisy);
    else if(channel == 3)
      rect(legend_width+spectrum_width+devide_space+binsperband*i, thisy+spectrum_height+devide_space, binsperband, spectrum_height-thisy);


    // update decays
    if (peak_age[channel][i] < peak_hold_time) {
      ++peak_age[channel][i];
    } else {
      peaks[channel][i] -= 2.0;
      if (peaks[channel][i] < 0) { peaks[channel][i] = 0; }
    }
  }
}

void drawSpectrum(int channel)
{
  // now draw current spectrum in brighter blue
  stroke(37, 116, 169);
  noFill();
  for(int i = 0; i < spectrum_width; i++)  {
    // draw the line for frequency band i using dB scale
    float val = dB_scale*(20*((float)Math.log10(fft.getBand(i))) + gain);
    if (fft.getBand(i) == 0) {   val = -200;   }  // avoid log(0)
    int y = spectrum_height - Math.round(val);
    if (y > spectrum_height) { y = spectrum_height; }

    if(channel == 0)
      line(legend_width+i, spectrum_height, legend_width+i, y);
    else if(channel == 1)
      line(legend_width+spectrum_width+devide_space+i, spectrum_height, legend_width+spectrum_width+devide_space+i, y);
    else if(channel == 2)
      line(legend_width+i, 2*spectrum_height+devide_space, legend_width+i, spectrum_height+devide_space+y);
    else if(channel == 3)
      line(legend_width+spectrum_width+devide_space+i, 2*spectrum_height+devide_space, legend_width+spectrum_width+devide_space+i, spectrum_height+devide_space+y);

    // update the peak record
    // which peak bin are we in?
    int peaksi = i/binsperband;
    if (val > peaks[channel][peaksi]) {
      peaks[channel][peaksi] = val;
      // reset peak age counter
      peak_age[channel][peaksi] = 0;
    }
  }
}

void drawFrequencyAxis(int channel)
{
  // add legend
  // frequency axis
  fill(255);
  stroke(255);
  

  if(channel == 0)
    line(legend_width,spectrum_height,legend_width+spectrum_width,spectrum_height); // horizontal line
  else if(channel == 1)
    line(legend_width+spectrum_width+devide_space,spectrum_height,legend_width+spectrum_width*2+devide_space,spectrum_height); // horizontal line
  else if(channel == 2)
    line(legend_width,2*spectrum_height+devide_space,legend_width+spectrum_width,2*spectrum_height+devide_space); // horizontal line
  else if(channel == 3)
    line(legend_width+spectrum_width+devide_space,2*spectrum_height+devide_space,legend_width+spectrum_width*2+devide_space,2*spectrum_height+devide_space); // horizontal line

  // x,y address of text is immediately to the left of the middle of the letters 
  textAlign(CENTER,TOP);
  for (float freq = 0.0; freq < in.sampleRate()/2; freq += 2000.0) {
    int x = legend_width;
    int y = spectrum_height;
    if(channel == 0) {
      x = x + fft.freqToIndex(freq); // which bin holds this frequency
    }
    else if(channel == 1) {
      x = x + spectrum_width+devide_space+fft.freqToIndex(freq); // which bin holds this frequency
    }
    else if(channel == 2) {
      x = x + fft.freqToIndex(freq); // which bin holds this frequency
      y = 2*spectrum_height+devide_space;
    }
    else if(channel == 3) {
      x = x + spectrum_width+devide_space+fft.freqToIndex(freq); // which bin holds this frequency
      y = 2*spectrum_height+devide_space;
    }

    line(x,y,x,y+4); // tick mark
    text(Math.round(freq/1000) +"kHz", x, y+5); // add text label
  }
}

void drawLevelAxis(int channel)
{
  int x = 0;
  if(channel == 0 || channel == 2)
    x = legend_width;
  else if(channel == 1 || channel == 3)
    x = legend_width+spectrum_width+devide_space;

  if(channel == 0 || channel == 1)
    line(x,0,x,spectrum_height); // vertictal line
  else if(channel == 2 || channel == 3)
    line(x,spectrum_height+devide_space,x,spectrum_height*2+devide_space); // vertictal line
  
  textAlign(RIGHT,CENTER);
  for (float level = -100.0; level < 100.0; level += 20.0) {
    int y = 0;
    if(channel == 0 || channel == 1)
      y = spectrum_height - (int)(dB_scale * (level+gain));
    else if(channel == 2 || channel == 3)
      y = 2*spectrum_height+devide_space - (int)(dB_scale * (level+gain));
    line(x,y,x-3,y);
    text((int)level+" dB",x-5,y);
  }
}


