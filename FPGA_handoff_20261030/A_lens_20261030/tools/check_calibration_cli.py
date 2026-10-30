"""Exercise real image detection and native-file calibration CLI on synthetic poses.

All images in this check are synthetic pinhole fixtures, never real camera evidence.
"""
from pathlib import Path
import datetime,hashlib,json,os,shutil,subprocess,sys
sys.path.insert(0,'C:/D/FPGA/A_software_20261024/deps')
import cv2,numpy as np
ROOT=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()

def main():
    cv2.setNumThreads(2)
    out=ROOT/'verification'/('calibration_cli_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
    data=out/'中文合成标定样本';train=data/'训练集';val=data/'独立验证集';train.mkdir(parents=True);val.mkdir()
    rng=np.random.default_rng(20261030);square=22.;K=np.array([[1450.,0,959.5],[0,1440.,539.5],[0,0,1]])
    outer=np.array([[-square,-square,0],[9*square,-square,0],[9*square,6*square,0],[-square,6*square,0]],np.float64)
    texture=np.zeros((420,600),np.uint8)
    for y in range(7):
        for x in range(10):texture[y*60:(y+1)*60,x*60:(x+1)*60]=235 if (x+y)%2 else 20
    texture=cv2.cvtColor(texture,cv2.COLOR_GRAY2BGR);corners=np.float32([[0,0],[599,0],[599,419],[0,419]])
    records=[]
    for i in range(28):
        for attempt in range(100):
            r=rng.uniform([-.45,-.5,-.35],[.45,.5,.35]);R,_=cv2.Rodrigues(r);center=R@np.array([4*square,2.5*square,0.])
            z=rng.uniform(650,950);cx=rng.uniform(400,1500);cy=rng.uniform(280,800)
            t=np.array([(cx-K[0,2])*z/K[0,0],(cy-K[1,2])*z/K[1,1],z])-center
            quad,_=cv2.projectPoints(outer,r,t,K,np.zeros(5));quad=quad.reshape(4,2)
            if np.all(quad[:,0]>30) and np.all(quad[:,0]<1890) and np.all(quad[:,1]>30) and np.all(quad[:,1]<1050):break
        else:raise AssertionError('Synthetic pose placement failed')
        image=cv2.warpPerspective(texture,cv2.getPerspectiveTransform(corners,quad.astype(np.float32)),(1920,1080),flags=cv2.INTER_LINEAR,borderValue=(150,150,150))
        path=(train if i<20 else val)/('合成棋盘_%02d.png'%i)
        ok,encoded=cv2.imencode('.png',image);assert ok;path.write_bytes(encoded.tobytes())
        records.append({'file':str(path),'sha256':sha(path),'synthetic':True,'rvec':r.tolist(),'tvec':t.tolist()})
    settings=out/'synthetic_settings.json';settings.write_text(json.dumps({'synthetic_test':True,'not_real_camera_evidence':True,'source':'Generated pinhole chessboard rasters'}))
    output=out/'标定输出';tool=ROOT/'tools/camera_calibration.py'
    env=os.environ.copy();env['PYTHONIOENCODING']='utf-8';env['OPENCV_FOR_THREADS_NUM']='2'
    argv=[sys.executable,str(tool),'--train',str(train),'--validation',str(val),'--settings',str(settings),'--square-mm',str(square),'--output',str(output)]
    print('CALIBRATION_CLI '+str(out),flush=True)
    with (out/'cli.log').open('w',encoding='utf-8') as log:
        p=subprocess.run(argv,env=env,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
    if p.returncode:raise RuntimeError(str(out/'cli.log'))
    result=json.loads((output/'camera_profile.json').read_text(encoding='utf-8'))
    assert result['evidence']['train_views']==20 and result['evidence']['held_out_views']==8
    assert result['deploy_to_fpga'] is False and result['camera_user_context']['synthetic_test'] is True
    assert result['evidence']['train_rms_px']<.3 and result['evidence']['validation_pose_fit_rms_px']<.3
    assert set(json.loads((output/'hardware_parameters.json').read_text()))=={'FX_Q16','FY_Q16','CX_Q16','CY_Q16','INV_FX_Q30','INV_FY_Q30','K1_Q26','K2_Q26','P1_Q26','P2_Q26'}
    # Independent held-out files must remain distinct even when their names differ.
    shutil.copyfile(train/'合成棋盘_00.png',val/'重复训练图.png')
    argv[-1]=str(out/'必须拒绝的输出')
    with (out/'duplicate_rejection.log').open('w',encoding='utf-8') as log:
        p=subprocess.run(argv,env=env,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
    assert p.returncode!=0 and 'share identical image content' in (out/'duplicate_rejection.log').read_text(encoding='utf-8')
    assert not (out/'必须拒绝的输出').exists()
    manifest={'scope':__doc__,'images':records,'source_sha256':{str(p):sha(p) for p in [tool,ROOT/'tools/board_geometry.py',Path(__file__)]},
              'synthetic_ground_truth_K':K.tolist(),'synthetic_distortion':[0]*5,'training_and_validation_disjoint':True}
    (out/'inputs.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False),encoding='utf-8')
    record={'passed':True,'hardware_accessed':False,'real_camera_or_optical_acceptance':False,'scope':__doc__,
            'native_images_detected':28,'unicode_file_paths':True,'duplicate_cross_set_rejected':True,
            'train_rms_px':result['evidence']['train_rms_px'],'validation_pose_fit_rms_px':result['evidence']['validation_pose_fit_rms_px'],
            'inputs_sha256':sha(out/'inputs.json'),'profile_sha256':sha(output/'camera_profile.json'),'cli_log_sha256':sha(out/'cli.log')}
    (out/'verification.json').write_text(json.dumps(record,indent=2));print(json.dumps({'directory':str(out),**record},indent=2))

if __name__=='__main__':main()
