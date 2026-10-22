"""Regenerate synthetic 0.2-second fixtures. Requires ffmpeg and mutagen; tests don't."""
from pathlib import Path
import struct, zlib, subprocess
from mutagen.id3 import ID3, TIT2, TPE1, TALB, TXXX, USLT, APIC, TRCK, COMM
from mutagen.flac import FLAC, Picture
from mutagen.mp4 import MP4, MP4Cover
from mutagen.apev2 import APEv2
root = Path(__file__).parent / 'Tags'
root.mkdir(exist_ok=True)
def chunk(kind, data):
    return struct.pack('>I',len(data)) + kind + data + struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR',struct.pack('>2I5B',2,2,8,2,0,0,0)) + chunk(b'IDAT',zlib.compress((b'\0'+bytes([40,100,180])*2)*2)) + chunk(b'IEND',b'')
(root / 'cover.png').write_bytes(png)
subprocess.run(['ffmpeg','-v','error','-y','-i',str(root/'cover.png'),'-frames:v','1',str(root/'cover.jpg')],check=True)
for name, codec, ext in [('id3v3','libmp3lame','mp3'),('id3v4','libmp3lame','mp3'),('vorbis','flac','flac'),('aac','aac','m4a'),('alac','alac','m4a')]:
    path = root / f'{name}.{ext}'
    subprocess.run(['ffmpeg','-v','error','-y','-f','lavfi','-i','sine=frequency=440:duration=0.2','-c:a',codec,str(path)],check=True)
    if ext == 'mp3':
        tags = ID3(path)
        tags.add(TIT2(encoding=3,text=['Original']))
        tags.add(TPE1(encoding=3,text=['Artist A','Artist B']))
        tags.add(TALB(encoding=3,text=['Album']))
        tags.add(TRCK(encoding=3,text=['2/12']))
        tags.add(TXXX(encoding=3,desc='REPLAYGAIN_TRACK_GAIN',text=['-3.0 dB']))
        tags.add(TXXX(encoding=3,desc='CUSTOM_KEEP',text=['untouched']))
        tags.add(COMM(encoding=3,lang='eng',desc='',text=['Comment']))
        tags.add(USLT(encoding=3,lang='eng',desc='',text='Lyrics'))
        for kind in [3,4]: tags.add(APIC(encoding=3,mime='image/png',type=kind,desc=f'Image {kind}',data=png))
        tags.save(path,v1=2,v2_version=3 if name=='id3v3' else 4,v23_sep=None)
        # Coexisting APE tags exercise selective updates and legacy cleanup.
        ape=APEv2(); ape['Title']='Original'; ape['Track']='2/12'; ape['CUSTOM_APE']='keep'; ape.save(path)
    elif ext == 'flac':
        tags=FLAC(path)
        for key,value in {'title':['Original'],'artist':['Artist A','Artist B'],'album':['Album'],'tracknumber':['2/12'],'lyrics':['Lyrics'],'comment':['Comment'],'REPLAYGAIN_TRACK_GAIN':['-3.0 dB'],'CUSTOM_KEEP':['untouched']}.items(): tags[key]=value
        for kind in [3,4]:
            pic=Picture(); pic.type=kind; pic.mime='image/png'; pic.desc=f'Image {kind}'; pic.width=1; pic.height=1; pic.depth=16; pic.data=png; tags.add_picture(pic)
        tags.save()
    else:
        tags=MP4(path)
        tags.update({'©nam':['Original'],'©ART':['Artist A','Artist B'],'©alb':['Album'],'trkn':[(2,12)],'©lyr':['Lyrics'],'©cmt':['Comment'],'----:com.apple.iTunes:CUSTOM_KEEP':[b'untouched'],'covr':[MP4Cover(png,imageformat=MP4Cover.FORMAT_PNG),MP4Cover(png,imageformat=MP4Cover.FORMAT_PNG)]})
        tags.save()
# Separate multiple lyrics fixture.
import shutil
shutil.copyfile(root/'id3v4.mp3',root/'multiple-lyrics.mp3')
tags=ID3(root/'multiple-lyrics.mp3'); tags.add(USLT(encoding=3,lang='chi',desc='translation',text='另一组歌词')); tags.save(root/'multiple-lyrics.mp3',v2_version=4)

shutil.copyfile(root/'id3v4.mp3',root/'synchronized-lyrics.mp3')
from mutagen.id3 import SYLT
tags=ID3(root/'synchronized-lyrics.mp3'); tags.delall('USLT'); tags.add(SYLT(encoding=3,lang='eng',format=2,type=1,text=[('Synchronized text',1000)])); tags.save(root/'synchronized-lyrics.mp3',v2_version=4)
