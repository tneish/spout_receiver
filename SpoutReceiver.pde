//    
//    Using Spot 2.007 https://spout.zeal.co
//

import java.nio.*;
import java.net.*;
import java.time.*;
import java.util.LinkedList;
import java.util.Queue;
import java.util.Collections;
// IMPORT THE SPOUT LIBRARY
import spout.*;

// The first time that receiveTexure of receiveImage are called, 
// the PGraphics or PImage objects are initialized with the size
// of the sender that the receiver connects to. Thereafter, the
// dimensions are changed to match the sender.
PImage img; // Image to receive a texture

// CONFIG
int num_neopixels = 200;
String tree_host = "10.0.1.26";
int tree_host_port = 5705;
int buffer_depth_millis = 1000;  //ms. Covers transport delay + jitter.  Same as audio. 

// FRAME DATA
Spout spout;
int[] pixels_copy;
int[] tree_frame = new int[num_neopixels];  // rgbw, 32bits per pixel

// TRANSPORT STUFF
ByteBuffer byte_buffer = ByteBuffer.allocate(16 + tree_frame.length * 4);  //2xint64 timestamp + int32 pixels
DatagramSocket udp_socket;
InetAddress address_tree;

// TIME STUFF
long ts_ms;
Instant frame_instant;   // frame timestamp
long delay_compensation_millis = 0;  // transport delay + source/sink clock diff
Queue<Long> delay_samples = new LinkedList<>();
int max_samples = 40;  // sliding window (roughly 20-40 seconds)

void setup() {
  
  // Initial window size
  size(640, 640, P3D);
  
  // Screen text size
  textSize(18);

  // Needed for resizing the window to the sender size
  // Processing 3+ only
  surface.setResizable(true);
  
  // CREATE A NEW SPOUT OBJECT
  spout = new Spout(this);

  try {
    udp_socket = new DatagramSocket();
    address_tree = InetAddress.getByName(tree_host);
  } catch (Exception e) {
    e.printStackTrace();
  }

  // OPTION : Specify a sender to connect to.
  // The active sender will be detected by default,
  // but you can specify the name of the sender to receive from.
  // The receiver will then attempt to connect to that sender
  // spout.setReceiverName("Spout Demo Sender");
  
} 

void linear_scan() {

    background(127);

    // Linear scan:
    
    int inc = (width * height) / num_neopixels;
    // string 1
    for (int i = 0, x = 0; i < inc*50; i+=inc, x+=10) {
      fill(pixels_copy[i]);
      rect(x, pixelHeight/2, 10, 10);
    }
    
    // string 2
    for (int i = inc*50, x = 0; i < inc*100; i+=inc, x+=10) {
      fill(pixels_copy[i]);
      rect(x, 10 + pixelHeight/2, 10, 10);
    }
    
    // string 3
    for (int i = inc*100, x = 0; i < inc*150; i+=inc, x+=10) {
      fill(pixels_copy[i]);
      rect(x, 20 + pixelHeight/2, 10, 10);
    }
    
    // string 4
    for (int i = inc*150, x = 0; i < inc*200; i+=inc, x+=10) {
      fill(pixels_copy[i]);
      rect(x, 30 + pixelHeight/2, 10, 10);
    }    

}


void send_frame() {
  // PACKET FORMAT
  // int64 source timestamp (for delay compensation)
  // int64 timestamp to display on tree
  // int32[] pixel values in frame
  byte_buffer.clear();
  // add buffer depth to display timestamp
  // current time in milliseconds since the java/unix epoch (1970-01-01T00:00:00Z)
  if (delay_compensation_millis < 0) {
    ts_ms = frame_instant.toEpochMilli() + buffer_depth_millis + delay_compensation_millis;
  } else {
    ts_ms = frame_instant.toEpochMilli() + buffer_depth_millis - delay_compensation_millis;
  }
  //ts_ms = frame_instant.toEpochMilli() + delay_compensation_millis;
  byte_buffer.putLong(frame_instant.toEpochMilli());
  byte_buffer.putLong(ts_ms);
  for (int i : tree_frame) {
    byte_buffer.putInt(i);
  }
  byte[] buf = byte_buffer.array();

  DatagramPacket udp_packet = new DatagramPacket(
        buf, buf.length, address_tree, tree_host_port);
  try {
    udp_socket.send(udp_packet);
  } catch (Exception e) {
    e.printStackTrace();
  }

}


void quadrants_four_arcs() {
  
  background(127);
  int np = 50;  // neopixels per string/quadrant
  int p = 0;  // pointer into tree_frame array
  // cartesian co-ords of neopixel.
  // x = r cos θ , y = r sin θ
  int x, y;   
  float r[] = {1.0, 0.75, 0.5, 0.25};  // radius
  float theta[] = {0, HALF_PI, PI, PI+HALF_PI, TWO_PI};  // radians

  // neopixels are placed in the same order they appear on the string of neopixels on the tree
  // (back and forwards and one 50-neopixel string per quadrant)
  for (int t = 0; t < 4; t += 1) {  // for each quadrant/string of neopixels
    //p = t*50;
    for (int i = 0; i < 4; i += 2) {  // repeat twice (4 arcs)
      // clock-wise around the tree, one quarter turn
      // number of neopixels on r=1 arc is 50 * 1/(1+0.75+0.5+0.25) = 20
      // (arc length = r * theta)
      for (float th=theta[t]; th < theta[t+1]; th+=HALF_PI/(np*r[i]/(1+0.75+0.5+0.25))) {
        x = pixelWidth/2 - 1 + int(floor(r[i]*cos(th)*((pixelWidth-1)/2)));
        y = pixelHeight/2 - 1 + int(floor(r[i]*sin(th)*((pixelHeight-1)/2)));
        if (p < t*np + np) {  // float compound inaccuracy gives + 1 
          System.arraycopy(pixels_copy, y*width+x, tree_frame, p, 1);  // want copy, not ref
          p+=1;
          rectMode(CENTER);
          fill(pixels_copy[y*width+x]);
          rect(x, y, 10, 10);
        }
      }
      // anti-clockwise, one quarter turn
      for (float th=theta[t+1]; th > theta[t]; th-=HALF_PI/(np*r[i+1]/(1+0.75+0.5+0.25))) {
        x = pixelWidth/2 - 1 + int(floor(r[i+1]*cos(th)*((pixelWidth-1)/2)));
        y = pixelHeight/2 - 1 + int(floor(r[i+1]*sin(th)*((pixelHeight-1)/2)));
        if (p < t*np + np) {  // float compound inaccuracy gives + 1 
          System.arraycopy(pixels_copy, y*width+x, tree_frame, p, 1);  // want copy, not ref
          p+=1;
          rectMode(CENTER);
          fill(pixels_copy[y*width+x]);
          rect(x, y, 10, 10);
        }
      }
    }
  }
  //if(spout.getSenderFrame() % 300 == 0) {
  //  for (int i = 0; i < num_neopixels; i++) {
  //    println(i + ": " + tree_frame[i]);
  //  }
  //  println("-----------------------");
  //}
  
}

void update_delay_compensation() {
  byte[] buffer = new byte[1024];
  DatagramPacket packet = new DatagramPacket(buffer, buffer.length);
  try {
    udp_socket.setSoTimeout(1); // ms
    udp_socket.receive(packet);
    // Extract the first two 8-byte long values
    ByteBuffer b = ByteBuffer.wrap(buffer);
    long ts_source = b.getLong();
    long ts_sink = b.getLong();
    if (delay_samples.size() < max_samples) {
      delay_samples.offer(ts_sink - ts_source);
    } else {
      delay_samples.remove();
      delay_samples.offer(ts_sink - ts_source);
    }
    delay_compensation_millis = Collections.min(delay_samples);
    println("ts_source: " + ts_source + "; ts_sink: " + ts_sink + ".");
    long diff = ts_sink - ts_source;
    println("sink - source = " + diff + ".");
    println("delay_compensation_millis = " + delay_compensation_millis);

  } catch (Exception e) {
    return;  // Just skip it. e.g. if no packet waiting
  }

}

void draw() {
  
    //  
    // RECEIVE FROM A SENDER
    //
      
    // OPTION 1: Receive and draw the texture
    //if(spout.receiveTexture())
    //    spout.drawTexture();
    
    // OPTION 2: Receive into PGraphics
    // pgr = spout.receiveTexture(pgr);
    // if(pgr != null) {
    //   image(pgr, 0, 0, width/2, height/2);
    //   loadPixels();
    //   showInfo();
    // }

    // OPTION 3: Receive into PImage texture
    img = spout.receiveTexture(img);
    
    frame_instant = Instant.now();  // timestamp source
    
    if(img != null) {
      image(img, 0, 0, width, height);
    }

    loadPixels();
    pixels_copy = new int[width*height];
    System.arraycopy(pixels, 0, pixels_copy, 0, width*height);  // avoids tearing, or unnecessary?

    quadrants_four_arcs();
    
    if (spout.isReceiverConnected()) {
      send_frame();
      update_delay_compensation();
    }

    // Option: resize the window to match the sender
    spout.resizeFrame();

    // Display sender info
    showInfo();

}

void showInfo() {
  
    fill(255);
  
    if(spout.isReceiverConnected()) {
      
        text("Receiving from : " + spout.getSenderName() + "  (" 
             + spout.getSenderWidth() + "x" 
             + spout.getSenderHeight() + " - "
             + spout.getSenderFormatName() + ")", 15, 30);
      
        // Report sender fps and frame number if the option is activated
        // Applications < Spout 2.007 will have no frame information
        if(spout.getSenderFrame() > 0) {
          text("fps  " + spout.getSenderFps() + "  :  frame "
               + spout.getSenderFrame(), 15, 50);
        }
        
        //text("pixel [0,0] is " + pixels[0], 15, 70);
       
    }
    else {
      text("No sender", 30, 30);
    }
}

// RH click to select a sender
void mousePressed() {
  // SELECT A SPOUT SENDER
  if (mouseButton == RIGHT) {
    // Bring up a dialog to select a sender.
    // SpoutSettings must have been run at least once
    // to establish the location of "SpoutPanel"
    spout.selectSender();
  }
}
      
