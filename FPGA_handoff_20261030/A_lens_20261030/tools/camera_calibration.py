"""Fit the supported Brown k1/k2/p1/p2 model from native training images.
Validation images are a separate input; never use them for fitting intrinsics.
"""
from pathlib import Path
import argparse,hashlib,json,sys,math
sys.path.insert(0,'C:/D/FPGA/A_software_20261024/deps')
sys.path.insert(0,'C:/D/FPGA/A_software_20261024/reference/B_lens_v2/python')
import cv2,numpy as np
from brect.calibration import load_calibration
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()

def object_grid(columns,rows,square_mm):
 if not(3<=columns<=40 and 3<=rows<=40 and math.isfinite(square_mm) and square_mm>0):raise ValueError('Invalid measured board dimensions')
 p=np.zeros((columns*rows,3),np.float32);p[:,:2]=np.mgrid[:columns,:rows].T.reshape(-1,2)*square_mm;return p

def fit_points(objects,images,size):
 if len(images)<8 or len(objects)!=len(images):raise ValueError('At least8 training poses are needed')
 flags=cv2.CALIB_FIX_K3|cv2.CALIB_FIX_K4|cv2.CALIB_FIX_K5|cv2.CALIB_FIX_K6
 rms,K,D,rvecs,tvecs=cv2.calibrateCamera(objects,images,size,None,None,flags=flags)
 if not np.isfinite(K).all() or not np.isfinite(D).all() or not np.isfinite(rms):raise ValueError('Non-finite calibration')
 D=D.ravel();assert len(D)==5 and D[4]==0
 return float(rms),K,D,rvecs,tvecs

def per_view(objects,images,K,D,rvecs=None,tvecs=None):
 errors=[]
 for j,(obj,img) in enumerate(zip(objects,images)):
  if rvecs is None:
   ok,r,t=cv2.solvePnP(obj,img,K,D,flags=cv2.SOLVEPNP_ITERATIVE)
   if not ok:raise ValueError('Validation pose fitting failed')
  else:r,t=rvecs[j],tvecs[j]
  pp,_=cv2.projectPoints(obj,r,t,K,D);e=np.linalg.norm(pp.reshape(-1,2)-img.reshape(-1,2),axis=1)
  errors.append({'rms_px':float(np.sqrt(np.mean(e*e))),'max_px':float(e.max())})
 return errors

def detect_folder(folder,cols,rows,size):
 from board_geometry import measure_grid
 files=sorted(p for p in folder.iterdir() if p.suffix.lower() in {'.png','.jpg','.jpeg','.bmp','.tif','.tiff'})
 if not files:raise ValueError('No supported images in '+str(folder))
 records=[];points=[];accepted=[]
 for p in files:
  payload=p.read_bytes()
  im=cv2.imdecode(np.frombuffer(payload,dtype=np.uint8),cv2.IMREAD_COLOR) if payload else None
  record={'file':str(p.resolve()),'sha256':sha(p),'accepted':False}
  if im is None:record['reason']='decode_failed'
  elif (im.shape[1],im.shape[0])!=size:record['reason']='native_size_mismatch_no_implicit_resize'
  else:
   ok,c=cv2.findChessboardCornersSB(cv2.cvtColor(im,cv2.COLOR_BGR2GRAY),(cols,rows),flags=cv2.CALIB_CB_NORMALIZE_IMAGE|cv2.CALIB_CB_EXHAUSTIVE)
   if not ok:record['reason']='complete_board_not_detected'
   else:
    extent=np.ptp(c.reshape(-1,2),axis=0)
    if min(extent)<80:record['reason']='board_too_small'
    else:record.update(accepted=True,corners=c.reshape(-1,2).tolist(),raw_grid=measure_grid(c.reshape(rows,cols,2)));points.append(c.astype(np.float32));accepted.append(p)
  records.append(record)
 return points,records,accepted

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--train',type=Path,required=True);ap.add_argument('--validation',type=Path,required=True);ap.add_argument('--settings',type=Path,required=True);ap.add_argument('--square-mm',type=float,required=True);ap.add_argument('--columns',type=int,default=9);ap.add_argument('--rows',type=int,default=6);ap.add_argument('--width',type=int,default=1920);ap.add_argument('--height',type=int,default=1080);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 if a.output.exists():ap.error('Output already exists; preserve previous calibration')
 if a.train.resolve()==a.validation.resolve():ap.error('Training and validation folders must differ')
 size=(a.width,a.height);obj=object_grid(a.columns,a.rows,a.square_mm);settings=json.loads(a.settings.read_text(encoding='utf-8'))
 train,tr,tf=detect_folder(a.train,a.columns,a.rows,size);val,vr,vf=detect_folder(a.validation,a.columns,a.rows,size)
 if len(train)<20 or len(val)<8:raise ValueError(f'Need at least20 detected training and8 held-out validation views; found {len(train)}/{len(val)}')
 th=[sha(p) for p in tf];vh=[sha(p) for p in vf]
 if len(set(th))!=len(th) or len(set(vh))!=len(vh):raise ValueError('Duplicate images within calibration set')
 if set(th)&set(vh):raise ValueError('Training and validation share identical image content')
 rms,K,D,rv,tv=fit_points([obj]*len(train),train,size);validation=per_view([obj]*len(val),val,K,D)
 pertrain=per_view([obj]*len(train),train,K,D,rv,tv)
 from board_geometry import measure_grid
 lines=[]
 for pts in val:
  fixed=cv2.undistortPoints(pts,K,D,P=K).reshape(a.rows,a.columns,2)
  lines.append({'raw':measure_grid(pts.reshape(a.rows,a.columns,2)),'corrected':measure_grid(fixed)})
 allpts=np.concatenate(train).reshape(-1,2);bounds=np.array([allpts.min(axis=0),allpts.max(axis=0)])
 profile={'status':'new_camera_calibration_pending_optical_acceptance','deploy_to_fpga':False,'profile_id':a.output.name,'camera_user_context':settings,'video':{'width':a.width,'height':a.height,'coordinate_policy':'Exact native decoded raster. No resize, EXIF rotation or geometric warp.'},'target':{'inner_corners':[a.columns,a.rows],'square_mm_measured':a.square_mm},'model':{'K':K.tolist(),'distortion_opencv_order':D.tolist(),'k1':float(D[0]),'k2':float(D[1]),'p1':float(D[2]),'p2':float(D[3]),'k3_fixed':0.0},'evidence':{'train_views':len(train),'held_out_views':len(val),'train_rms_px':rms,'training_per_view':pertrain,'validation_per_view_pose_fit':validation,'validation_pose_fit_rms_px':float(np.sqrt(np.mean([v['rms_px']**2 for v in validation]))),'held_out_line_diagnostics':lines,'training_corner_bounds_px':bounds.tolist(),'training_width_coverage':float(np.ptp(allpts[:,0])/a.width),'training_height_coverage':float(np.ptp(allpts[:,1])/a.height)},'remaining':'Confirm lens/focus/camera processing settings, independently inspect calibration stability and real-board optical results. MTF/SFR and end-to-end latency are separate measurements.'}
 a.output.mkdir(parents=True);p=a.output/'camera_profile.json';p.write_text(json.dumps(profile,indent=2,ensure_ascii=False),encoding='utf-8');hw=load_calibration(p,size).to_hardware();(a.output/'hardware_parameters.json').write_text(json.dumps(hw,indent=2))
 inp={'settings_file':str(a.settings.resolve()),'settings_sha256':sha(a.settings),'training':tr,'validation':vr,'tool_sha256':sha(__file__),'opencv_version':cv2.__version__,'numpy_version':np.__version__};(a.output/'inputs.json').write_text(json.dumps(inp,indent=2,ensure_ascii=False),encoding='utf-8')
 print(json.dumps({'profile':str(p.resolve()),'training_rms_px':rms,'validation_rms_px':profile['evidence']['validation_pose_fit_rms_px'],'deploy_to_fpga':False},ensure_ascii=False))
if __name__=='__main__':main()
