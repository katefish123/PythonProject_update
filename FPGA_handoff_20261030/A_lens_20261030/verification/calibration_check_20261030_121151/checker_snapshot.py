from pathlib import Path
import sys,json,hashlib,datetime,shutil
sys.path.insert(0,str(Path(__file__).parent))
from camera_calibration import *
b=Path(__file__).resolve().parents[1];out=b/'verification'/('calibration_check_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'));out.mkdir()
rng=np.random.default_rng(20261030);size=(1920,1080);K=np.array([[1599.,0,933.5],[0,1596.4,525.3],[0,0,1.]],np.float64);D=np.array([.0114,-.05086,-.00407,-.00362,0.],np.float64);obj=object_grid(9,6,19.)
objects=[];images=[];angles=[]
for j in range(70):
 r=rng.uniform([-.6,-.6,-.3],[.6,.6,.3]);z=rng.uniform(330,650);tx=rng.uniform(-160,160)-76;ty=rng.uniform(-90,90)-47.5;t=np.array([tx,ty,z]);p,_=cv2.projectPoints(obj,r,t,K,D)
 if (p[:,:,0]<8).any() or (p[:,:,0]>1911).any() or (p[:,:,1]<8).any() or (p[:,:,1]>1071).any():continue
 p=(p+rng.normal(0,.025,p.shape)).astype(np.float32);objects.append(obj);images.append(p);angles.append({'r':r.tolist(),'t':t.tolist()})
assert len(images)>=40
nt=len(images)-10;rms,gotK,gotD,rv,tv=fit_points(objects[:nt],images[:nt],size);held=per_view(objects[nt:],images[nt:],gotK,gotD)
uv=np.stack(np.meshgrid(np.linspace(0,1919,31),np.linspace(0,1079,19)),axis=-1).reshape(-1,2).astype(np.float64)
# Compare normalized-ray inverse correction against the known generating camera.
a=cv2.undistortPoints(uv.reshape(-1,1,2),K,D,P=K).reshape(-1,2);c=cv2.undistortPoints(uv.reshape(-1,1,2),gotK,gotD,P=gotK).reshape(-1,2);maxmap=float(np.linalg.norm(a-c,axis=1).max())
assert rms<.06 and maxmap<.5 and max(abs(gotK[0,0]/K[0,0]-1),abs(gotK[1,1]/K[1,1]-1))<.005
for cols,rows,sq in [(2,6,19),(9,2,19),(9,6,0),(9,6,float('nan'))]:
 try:object_grid(cols,rows,sq)
 except ValueError:pass
 else:raise AssertionError('Invalid board accepted')
try:fit_points(objects[:7],images[:7],size)
except ValueError:pass
else:raise AssertionError('Too few poses accepted')
inputs={'scope':'Synthetic camera projection test only; no real calibration acceptance.','generator_K':K.tolist(),'generator_distortion':D.tolist(),'pose_parameters':angles,'seed':20261030,'training_views':nt,'held_out_views':10,'input_sha256':{str(p):sha(p) for p in [Path(__file__),b/'tools/camera_calibration.py',b/'tools/board_geometry.py']}}
np.savez_compressed(out/'synthetic_corners.npz',objects=np.array(objects),images=np.array(images));inputs['input_sha256'][str(out/'synthetic_corners.npz')]=sha(out/'synthetic_corners.npz');(out/'inputs.json').write_text(json.dumps(inputs,indent=2));shutil.copyfile(Path(__file__),out/'checker_snapshot.py')
result={'passed':True,'synthetic_only':True,'hardware_accessed':False,'real_optical_acceptance':False,'training_rms_px':rms,'held_out_rms_px':float(np.sqrt(np.mean([v['rms_px']**2 for v in held]))),'maximum_known_model_map_error_px':maxmap,'estimated_K':gotK.tolist(),'estimated_distortion':gotD.tolist(),'invalid_inputs_rejected':5,'input_manifest_sha256':sha(out/'inputs.json')};(out/'verification.json').write_text(json.dumps(result,indent=2));print(json.dumps({'directory':str(out),**result},indent=2))