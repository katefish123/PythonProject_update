"""Independent OpenCV example in ORIGINAL JPG coordinates, not camera pixels."""
from pathlib import Path
import hashlib
import json
import shutil
import cv2
import numpy as np

HERE=Path(__file__).resolve().parent
MATERIALS=HERE/'materials'
INPUTS={
 'original_black_chart.jpg':Path('C:/Users/Lenovo/AppData/Local/Temp/codex-clipboard-4dbd4c15-fa66-48f1-8ae4-d6f4207d5c69.jpg'),
 'board_black_chart_output.png':Path('C:/Users/Lenovo/AppData/Local/Temp/codex-clipboard-7fc8fda7-25b2-49fb-87fe-07a0092173dd.png'),
 'board_colored_chart_output.png':Path('C:/Users/Lenovo/AppData/Local/Temp/codex-clipboard-464238eb-ad39-4941-a8c1-a7bcea16f833.png')}

def main():
    MATERIALS.mkdir(exist_ok=True)
    source_manifest=[]
    for name,source in INPUTS.items():
        dest=MATERIALS/name
        shutil.copyfile(source,dest)
        source_manifest.append({'archive':str(dest),'original_path':str(source),
                                'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),
                                'space':'original_test_file' if name.startswith('original') else 'board_output_screenshot_not_raw_camera_input'})
    image=cv2.imread(str(MATERIALS/'original_black_chart.jpg'))
    black=np.all(image<=64,axis=2).astype('uint8')
    _,labels,stats,centers=cv2.connectedComponentsWithStats(black,8)
    candidates=[]
    for stat,center in zip(stats[1:],centers[1:]):
        x,y,w,h,area=map(int,stat)
        if 25<=w<=70 and 25<=h<=70 and area>500 and area/(w*h)>.8:
            candidates.append(center)
    assert len(candidates)==4, f'expected four compact black components, got {candidates}'
    upper=sorted(sorted(candidates,key=lambda p:p[1])[:2],key=lambda p:p[0])
    lower=sorted(sorted(candidates,key=lambda p:p[1])[2:],key=lambda p:p[0])
    source=np.float32([upper[0],upper[1],lower[1],lower[0]])
    target=np.float32([[0,0],[764,0],[764,1079],[0,1079]])
    forward=cv2.getPerspectiveTransform(source,target)
    mapped=cv2.perspectiveTransform(source[None,:,:],forward)[0]
    assert np.max(np.abs(mapped-target))<.001
    reference=cv2.warpPerspective(image,forward,(765,1080),flags=cv2.INTER_LINEAR)
    cv2.imwrite(str(HERE/'software_black_chart_765x1080.png'),reference)
    result={'status':'software_reference_only_not_board_acceptance','opencv_version':cv2.__version__,
            'materials':source_manifest,'original_jpg_size':[image.shape[1],image.shape[0]],
            'corner_space':'original JPG1586x992 pixel coordinates, NEVER1920x1080 camera coordinates',
            'source_black_component_centroids_TL_TR_BR_BL':source.tolist(),
            'target_size':[765,1080],'target_corners':target.tolist(),
            'forward_source_to_target_H':forward.tolist(),
            'target_ratio_policy':'Existing765x1080 convention retained; the printed640x480 text is not a target-aspect measurement.',
            'limitations':['No raw camera frame supplied; no real-camera selected centroids or H are inferred.',
                           'Output screenshots and original JPG are distinct coordinate spaces.',
                           'Four-point software warp does not prove printed grid is a metrically exact calibration chart.',
                           'The earlier black-only mismatch finding does not alone explain the black-marker board failure.']}
    (HERE/'software_black_chart_reference.json').write_text(json.dumps(result,indent=2)+'\n')
    print('PASS software reference corners mapped within0.001px; original JPG coordinates only')

if __name__=='__main__':main()
