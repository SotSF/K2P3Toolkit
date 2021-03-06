//==========================================================
// set resolution of your projector image/second monitor
// and name of your calibration file-to-be
int pWidth = 800;
int pHeight = 600; 
String calibFilename = "calibration.txt";


//==========================================================
//==========================================================

import javax.swing.JFrame;
import org.openkinect.freenect.*;
import org.openkinect.freenect2.*;
import org.openkinect.processing.*;

import gab.opencv.*;
import controlP5.*;
import Jama.*;

Kinect2 kinect;

OpenCV opencv;
ChessboardFrame frameBoard;
ChessboardApplet ca;
PVector[] depthMap;
PImage src;
ArrayList<PVector> foundPoints = new ArrayList<PVector>();
ArrayList<PVector> projPoints = new ArrayList<PVector>();
ArrayList<PVector> ptsK, ptsP;
PVector testPoint, testPointP;
boolean isSearchingBoard = false;
boolean calibrated = false;
boolean testingMode = false;
int cx, cy, cwidth;

void setup() 
{
  surface.setSize(1200, 768);
  
  textFont(createFont("Courier", 24));
  frameBoard = new ChessboardFrame();

  // set up kinect 
  kinect = new Kinect2(this);
  kinect.initDepth(); 
  kinect.initVideo();
  kinect.initRegistered();
  kinect.initIR();
  kinect.initDevice();
  
  opencv = new OpenCV(this, kinect.depthWidth, kinect.depthHeight);

  depthMap = new PVector[kinect.depthWidth*kinect.depthHeight];

  // matching pairs
  ptsK = new ArrayList<PVector>();
  ptsP = new ArrayList<PVector>();
  testPoint = new PVector();
  testPointP = new PVector();
  setupGui();
}

void draw() 
{
  // draw chessboard onto scene
  projPoints = drawChessboard(cx, cy, cwidth);

  // update depth map
  depthMap = depthMapRealWorld();

  src = kinect.getRegisteredImage();
  
  // mirroring
  for (int h = 0; h < kinect.depthHeight; h++)
  {
    for (int r = 0; r < kinect.depthWidth / 2; r++)
    {
      PVector temp = depthMap[h*kinect.depthWidth + r];
      depthMap[h*kinect.depthWidth + r] = depthMap[h*kinect.depthWidth + (kinect.depthWidth - r - 1)];
      depthMap[h*kinect.depthWidth + (kinect.depthWidth - r - 1)] = temp;
    }
  }
  
  // mirroring
  for (int h = 0; h < src.height; h++)
  {
    for (int r = 0; r < src.width / 2; r++)
    {
      int temp2 = src.get(r, h);   //h*src.width + r);
      src.set(r, h, src.get(src.width - r - 1, h));
      src.set(src.width - r - 1, h, temp2);
    }
  }

  opencv.loadImage(src);
  opencv.gray();

  if (isSearchingBoard)
    foundPoints = opencv.findChessboardCorners(4, 3);

  drawGui();
}

void drawGui() 
{
  background(0, 100, 0);

  // draw the RGB image
  pushMatrix();
  translate(30, 120);
  textSize(22);
  fill(255);
  image(src, 0, 0);
  
  // draw chessboard corners, if found
  if (isSearchingBoard) {
    int numFoundPoints = 0;
    for (PVector p : foundPoints) {
      if (getDepthMapAt((int)p.x, (int)p.y).z > 0) {
        fill(0, 255, 0);
        numFoundPoints += 1;
      }
      else  fill(255, 0, 0);
      ellipse(p.x, p.y, 5, 5);
    }
    if (numFoundPoints == 12)  guiAdd.show();
    else                       guiAdd.hide();
  }
  else  guiAdd.hide();
  if (calibrated && testingMode) {
    fill(255, 0, 0);
    ellipse(testPoint.x, testPoint.y, 10, 10);
  }
  popMatrix();

  // draw GUI
  pushMatrix();
  pushStyle();
  translate(kinect.depthWidth+70, 40); // this is black box
  fill(0);
  rect(0, 0, 450, 680); // blackbox size
  fill(255);
  text(ptsP.size()+" pairs", 26, guiPos.y+525);
  popStyle();
  popMatrix();
}

ArrayList<PVector> drawChessboard(int x0, int y0, int cwidth) {
  ArrayList<PVector> projPoints = new ArrayList<PVector>();
  ca.redraw();
  return projPoints;
}


void addPointPair() {
  if (projPoints.size() == foundPoints.size()) {
    println(getDepthMapAt((int) foundPoints.get(1).x, (int) foundPoints.get(1).y));
    for (int i=0; i<projPoints.size(); i++) {
      ptsP.add( projPoints.get(i) );
      ptsK.add( getDepthMapAt((int) foundPoints.get(i).x, (int) foundPoints.get(i).y) );
    }
  }
  guiCalibrate.show();
  guiClear.show();
}

PVector getDepthMapAt(int x, int y) {
  PVector dm = depthMap[kinect.depthWidth * y + x];
  
  return new PVector(dm.x, dm.y, dm.z);
}

void clearPoints() {
  ptsP.clear();
  ptsK.clear();
  guiSave.hide();
}

void saveC() {
  saveCalibration(calibFilename); 
}

void loadC() {
  println("load");
  loadCalibration(calibFilename);
  guiTesting.addItem("Testing Mode", 1);
}

void mousePressed() {
  if (calibrated && testingMode) {
    testPoint = new PVector(constrain(mouseX-30, 0, kinect.depthWidth-1), 
                            constrain(mouseY-120, 0, kinect.depthHeight-1));
    int idx = kinect.depthWidth * (int) testPoint.y + (int) testPoint.x;
    
    testPointP = convertKinectToProjector(depthMap[idx]);
  }
}


// all functions below used to generate depthMapRealWorld point cloud
PVector[] depthMapRealWorld()
{
  int[] depth = kinect.getRawDepth();
  int skip = 1;
  for (int y = 0; y < kinect.depthHeight; y+=skip) {
    for (int x = 0; x < kinect.depthWidth; x+=skip) {
        int offset = x + y * kinect.depthWidth;
        //calculate the x, y, z camera position based on the depth information
        PVector point = depthToPointCloudPos(x, y, depth[offset]);
        depthMap[kinect.depthWidth * y + x] = point;
      }
    }
    return depthMap;
}

//calculte the xyz camera position based on the depth data
PVector depthToPointCloudPos(int x, int y, float depthValue) {
  PVector point = new PVector();
  point.z = (depthValue);// / (1.0f); // Convert from mm to meters
  point.x = ((x - CameraParams.cx) * point.z / CameraParams.fx);
  point.y = ((y - CameraParams.cy) * point.z / CameraParams.fy);
  return point;
}

//camera information based on the Kinect v2 hardware
static class CameraParams {
  static float cx = 254.878f;
  static float cy = 205.395f;
  static float fx = 365.456f;
  static float fy = 365.456f;
  static float k1 = 0.0905474;
  static float k2 = -0.26819;
  static float k3 = 0.0950862;
  static float p1 = 0.0;
  static float p2 = 0.0;
}