/**
 * Copyright 2014 University of Bremen, Institute for Artificial Intelligence
 * Author: Thiemo Wiedemeyer <wiedemeyer@cs.uni-bremen.de>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Rotation
#define r00 %0.14e
#define r01 %0.14e
#define r02 %0.14e
#define r10 %0.14e
#define r11 %0.14e
#define r12 %0.14e
#define r20 %0.14e
#define r21 %0.14e
#define r22 %0.14e

// Translation
#define tx %0.14e
#define ty %0.14e
#define tz %0.14e

// Camera parameter upscaled depth
#define fxD %.14e
#define fyD %.14e
#define cxD %.14e
#define cyD %.14e
#define fxDInv (1.0f / fxD)
#define fyDInv (1.0f / fyD)

// Camera parameter color
#define fxC %.14e
#define fyC %.14e
#define cxC %.14e
#define cyC %.14e

// Clipping distances
#define zNear %d
#define zFar %d
#define zDist %.14e

// Size color image
#define heightC %d
#define widthC %d

// Size depth image
#define heightD %d
#define widthD %d

// Size raw depth image
#define heightR %d
#define widthR %d

// Set render buffer to zero
void kernel setZero(global ushort* rendered, global float *selDist){
  const uint i = get_global_id(0);
  rendered[i] = 0;
  selDist[i] = 10;
}

// Calculate 3d point, project them to color camera coordinate system and create rendered depth image
void kernel project(global const ushort *depth, global int4 *idx, global ushort *zImg, global float4 *dists, global float *selDist, global ushort *rendered){
  const uint i = get_global_id(0);

  const int xD = i % widthD;
  const int yD = i / widthD;

  const ushort d = depth[i];

  // Projection matrix coloumns
  const float4 projX = (float4)(r00, r01, r02, tx);
  const float4 projY = (float4)(r10, r11, r12, ty);
  const float4 projZ = (float4)(r20, r21, r22, tz);

  // Compute 3D point
  const float z = d / 1000.0f;
  const float4 point = (float4)((xD - cxD) * fxDInv * z, (yD - cyD) * fyDInv * z, z, 1.0f);

  // Rotate and translate
  const float3 projected = (float3)(dot(point, projX), dot(point, projY), dot(point, projZ));

  const float invZ = 1.0f / projected.z;

  // Compute projected image coordinates
  const float x = (fxD * projected.x) * invZ + cxD;
  const float y = (fyD * projected.y) * invZ + cyD;
  const short xL = (short)floor(x);
  const short yL = (short)floor(y);
  const short xH = xL + 1;
  const short yH = yL + 1;

  const float4 distXY = pown((float4)(x - xL, xH - x, y - yL, yH - y), 2);
  const float4 dist2 = (float4)(distXY.s0 + distXY.s2, distXY.s1 + distXY.s2, distXY.s0 + distXY.s3, distXY.s1 + distXY.s3);

  const int yLI = yL * widthD;
  const int yHI = yH * widthD;
  int4 indices = (int4)(yLI + xL, yLI + xH, yHI + xL, yHI + xH);

  const ushort zI = (ushort)(projected.z * 1000.0f);

  // Check if depth is valid and projection is inside the image
  if(xL < 0)
  {
    indices.s0 = indices.s2 = -1;
  }
  if(yL < 0)
  {
    indices.s0 = indices.s1 = -1;
  }
  if(xH >= widthD)
  {
    indices.s1 = indices.s3 = -1;
  }
  if(yH >= heightD)
  {
    indices.s2 = indices.s3 = -1;
  }
  if(indices.s0 >= 0)
  {
    selDist[indices.s0] = dist2.s0;
    rendered[indices.s0] = zI;
  }
  if(indices.s1 >= 0)
  {
    selDist[indices.s1] = dist2.s1;
    rendered[indices.s1] = zI;
  }
  if(indices.s2 >= 0)
  {
    selDist[indices.s2] = dist2.s2;
    rendered[indices.s2] = zI;
  }
  if(indices.s3 >= 0)
  {
    selDist[indices.s3] = dist2.s3;
    rendered[indices.s3] = zI;
  }

  idx[i] = indices;
  dists[i] = dist2;
  zImg[i] = zI;
}

// update rendered depth image to make sure nearest depth values are used
void kernel render(global const int4 *idx, global const ushort *zImg, global const float4 *dists, global float *selDist, global ushort *rendered){
  const uint i = get_global_id(0);

  const int4 index = idx[i];
  const ushort zI = zImg[i];
  const ushort thres = 0.01 * zI;
  const ushort zIThres = zI + thres;
  const float4 dist2 = dists[i];

  ushort zRen;
  zRen = rendered[index.s0];
  if(index.s0 >= 0 && ((abs_diff(zRen, zI) < thres && selDist[index.s0] > dist2.s0) || zRen > zIThres))
  {
    selDist[index.s0] = dist2.s0;
    rendered[index.s0] = zI;
  }
  zRen = rendered[index.s1];
  if(index.s1 >= 0 && ((abs_diff(zRen, zI) < thres && selDist[index.s1] > dist2.s1) || zRen > zIThres))
  {
    selDist[index.s1] = dist2.s1;
    rendered[index.s1] = zI;
  }
  zRen = rendered[index.s2];
  if(index.s2 >= 0 && ((abs_diff(zRen, zI) < thres && selDist[index.s2] > dist2.s2) || zRen > zIThres))
  {
    selDist[index.s2] = dist2.s2;
    rendered[index.s2] = zI;
  }
  zRen = rendered[index.s3];
  if(index.s3 >= 0 && ((abs_diff(zRen, zI) < thres && selDist[index.s3] > dist2.s3) || zRen > zIThres))
  {
    selDist[index.s3] = dist2.s3;
    rendered[index.s3] = zI;
  }
}

// Calculate 3d point, project them to color camera coordinate system and create rendered depth image
/*void kernel project(global const unsigned short *depth, global int *idx, global unsigned short *zImg, global unsigned short *rendered){
  const uint i = get_global_id(0);

  const int xD = i % widthD;
  const int yD = i / widthD;

  const ushort d = depth[i];

  // Projection matrix coloumns
  const float4 projX = (float4)(r00, r01, r02, tx);
  const float4 projY = (float4)(r10, r11, r12, ty);
  const float4 projZ = (float4)(r20, r21, r22, tz);

  // Compute 3D point
  const float z = d / 1000.0f;
  const float4 point = (float4)((xD - cxD) * fxDInv * z, (yD - cyD) * fyDInv * z, z, 1.0f);

  // Rotate and translate
  const float3 projected = (float3)(dot(point, projX), dot(point, projY), dot(point, projZ));

  const float invZ = 1.0f / projected.z;

  // Compute projected image coordinates
  const short xI = (short)((fxD * projected.x) * invZ + cxD);
  const short yI = (short)((fyD * projected.y) * invZ + cyD);

  // Check if depth is valid and projection is inside the image
  if(d >= zNear && d <= zFar && xI >= 0 && xI < widthD && yI >= 0 && yI < heightD)
  {
    const ushort zI = (ushort)(projected.z * 1000.0f);
    const int index = xI + yI * widthD;

    idx[i] = index;
    zImg[i] = zI;

    // Store in rendered image. Due to concurrency value can get overridden by other workers
    if(rendered[index] == 0 || zI < rendered[index])
    {
      rendered[index] = zI;
    }
  }
  else
  {
    idx[i] = -1;
    zImg[i] = 0;
  }
}

// update rendered depth image to make sure nearest depth values are used
void kernel render(global const int *idx, global const ushort *zImg, global ushort *rendered){
  const uint i = get_global_id(0);

  const int index = idx[i];
  const ushort zI = zImg[i];

  if(index >= 0)
  {
    if(zI < rendered[index])
    {
      rendered[index] = zI;
    }
  }
}*/

// remap depth image
void kernel remapDepth(global const ushort *in, global ushort *out, global const float *mapX, global const float *mapY)
{
  const uint i = get_global_id(0);

  const float x = mapX[i];
  const float y = mapY[i];
  const int xL = (int)floor(x);
  const int xH = xL + 1;
  const int yL = (int)floor(y);
  const int yH = yL + 1;

  if(xL < 0 || yL < 0 || xH >= widthR || yH >= heightR)
  {
    out[i] = 0;
    return;
  }

  const uint iLT = yL * widthR + xL;
  const uint iRT = iLT + 1;
  const uint iLB = iLT + widthR;
  const uint iRB = iLB + 1;

  const float4 p = (float4)(in[iLT], in[iRT], in[iLB], in[iRB]);
  int4 valid = isgreaterequal(p, (float4)(1));
  int count = abs(valid.s0 + valid.s1 + valid.s2 + valid.s3);

  if(count < 3)
  {
    out[i] = 0;
    return;
  }

  const float avg = (p.s0 + p.s1 + p.s2 + p.s3) / count;
  const float thres = 0.01 * avg;
  valid = isless(fabs(p - avg), (float4)(thres));
  count = abs(valid.s0 + valid.s1 + valid.s2 + valid.s3);

  if(count < 3)
  {
    out[i] = 0;
    return;
  }

  const float4 distXY = pown((float4)(x - xL, xH - x, y - yL, yH - y), 2);
  const float4 tmp = (float4)(sqrt(2.0));
  const float4 dist2 = (float4)(distXY.s0 + distXY.s2, distXY.s1 + distXY.s2, distXY.s0 + distXY.s3, distXY.s1 + distXY.s3);
  const float4 dist = select((float4)(0), tmp - sqrt(dist2), valid);
  const float sum = dist.s0 + dist.s1 + dist.s2 + dist.s3;

  out[i] = (dot(p, dist) / sum) + 0.5;
}
