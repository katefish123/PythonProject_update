"""Interpret trusted, decoded board counters without inferring optical success."""
def summarize(fields, previous, now):
    if not fields:
        return {'text':'板上检测\n诊断数据不可用\n请检查视频连接\n或打开板上诊断\n\n当前不能判断故障\n也不能判断验收通过\n\n原始记录保留在后台',
                'corrected_fps':None,'fields':{},'time':now,'unchanged_since':now}
    old=previous.get('fields',{}) if previous else {}
    mode='原始画面 RAW' if fields['pix_raw'] else '镜头校正'
    elapsed=now-previous['time'] if previous else 0
    same_epoch=(old and fields['corrected']>=old['corrected'] and
                fields['raw']>=old['raw'] and fields['pix_frame_id']>=old['pix_frame_id'])
    unchanged=bool(same_epoch and fields['pix_frame_id']==old['pix_frame_id'])
    since=previous['unchanged_since'] if unchanged else now
    update='观察中' if not same_epoch else ('停更，请检查' if unchanged and now-since>=2 else
                                         '本次未换图' if unchanged else '帧号正在推进')
    fps=None
    if same_epoch and elapsed>0 and not fields['pix_raw'] and not old['pix_raw']:
        fps=(fields['corrected']-old['corrected'])/elapsed
    rate=f'{fps:.1f} 张/秒' if fps is not None else '等待实测 / RAW时不计'
    valid='有完整图像标志' if fields['image_valid'] else '尚无完整图像'
    fault='未置位' if not fields['current_mask'] else '有故障，请保留现场'
    history='有故障记录' if fields['first_mask'] else '无记录'
    text=(f'板上检测\n模式：{mode}\n图像：{valid}\n更新：{update}\n校正发布：{rate}\n'
          f'图像年龄：{fields["age_ms"]} 毫秒\n当前故障：{fault}\n历史记录：{history}\n'
          f'接收缓存峰值：{fields["fifo_peak"]}/1024\n\n欠载：需查看板上 LED5\n'
          '帧号推进不等于实景正确\n帧率为采样区间估计\n清晰度 / 延迟仍需实测')
    return dict(text=text,corrected_fps=fps,fields=fields,time=now,unchanged_since=since)
