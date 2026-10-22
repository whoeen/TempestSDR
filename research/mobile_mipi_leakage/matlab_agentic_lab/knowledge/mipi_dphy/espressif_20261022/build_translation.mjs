import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
const {marked}=await import(process.argv[2] ? pathToFileURL(path.resolve(process.argv[2])).href : 'marked');
const files=['introduction_ko.md','part1_physical_ko.md','part2_packets_ko.md','part3_driver_ko.md','research_explanation_ko.md'];
let [intro,p1,p2,p3,end]=await Promise.all(files.map(f=>fs.readFile(path.join(here,f),'utf8')));
function deepen(text){
 let code=false;
 return text.split('\n').map(line=>{
  if(line.trimStart().startsWith(String.fromCharCode(96).repeat(3))){code=!code;return line;}
  return !code ? line.replace(/^(#{1,5})(\s+)/,(_,h,sp)=>'#'.repeat(h.length+1)+sp) : line;
 }).join('\n');
}
p1=deepen(p1);
p2=deepen(p2.replace(/^# .*\n/,'# 제2부 — 프로토콜 계층·DCS·색 형식\n').replace('Root가 만든','첨부 원본을 분할한'));
p3='## 제3부 — 드라이버 구성과 문제 해결\n\n'+deepen(p3);
const figures=[
 ['mipi_dsi_video.png','01_refresh.png','그림 1. MIPI-DSI 화면 갱신 과정'],
 ['mipi_dsi_layer.png','02_layers.png','그림 2. MIPI-DSI 계층 개념도'],
 ['mipi_dsi_stop.png','03_stop.png','그림 3. Stop·Escape·ACK 파형'],
 ['mipi_dsi_short_packet.png','04_short_packet.png','그림 4. Short packet 구성'],
 ['mipi_dsi_short_packet_example.png','05_short_timing.png','그림 5. LPDT short packet 타이밍'],
 ['mipi_dsi_long_paket.png','06_long_packet.png','그림 6. Long packet 구성'],
 ['mipi_dsi_long_packet_example.png','07_long_timing.png','그림 7. LPDT long packet 타이밍'],
 ['mipi_dsi_color_format.png','08_color.png','그림 8. 표시 색 정보의 24bit 확장 예']
];
let md=[intro,p1,p2,p3,end].join('\n\n---\n\n');
for(const [remote,local,alt] of figures){
 const re=new RegExp('(^[^\\n]*https://dl\\.espressif\\.com/AE/esp-dev-kits/'+remote.replaceAll('.','\\.')+'[^\\n]*$)','m');
 if(!re.test(md))throw Error('Missing figure target '+remote);
 md=md.replace(re,'!['+alt+'](assets/'+local+')\n\n$1');
}
md=md.replace('**그림: Lane 수 설정 — 캡처의 레지스터 표 번역**','![그림 9. EK79007 lane 수 설정 레지스터](assets/09_lane_register.png)\n\n원본 그림: [Lane Number Configuration](https://dl.espressif.com/AE/esp-dev-kits/mipi_dsi_lane_num.png)\n\n**그림: Lane 수 설정 — 캡처의 레지스터 표 번역**');
md=md.replace('**그림: 속도 범위 — 캡처의 고속 전송 규격 표 번역**','![그림 10. UI와 고속 전송 규격](assets/10_speed.png)\n\n원본 그림: [Speed Range](https://dl.espressif.com/AE/esp-dev-kits/mipi_dsi_speed.png)\n\n**그림: 속도 범위 — 캡처의 고속 전송 규격 표 번역**');
await fs.writeFile(path.join(here,'full_translation_ko.md'),md);
let body=marked.parse(md,{gfm:true}), count=0;
const headings=[];
body=body.replace(/<h([1-6])>([\s\S]*?)<\/h\1>/g,(_,n,text)=>{
 const id='section-'+(++count),level=Number(n);
 if(level<=3)headings.push({id,level,text:text.replace(/<[^>]+>/g,'')});
 return '<h'+n+' id="'+id+'">'+text+'</h'+n+'>';
});
for(const name of [...figures.map(x=>x[1]),'09_lane_register.png','10_speed.png']){
 const bytes=await fs.readFile(path.join(here,'assets',name));
 body=body.replaceAll('src="assets/'+name+'"','src="data:image/png;base64,'+bytes.toString('base64')+'"');
}
body=body.replace(/<table>/g,'<div class="table-wrap"><table>').replace(/<\/table>/g,'</table></div>');
body=body.replace(/<p><img ([\s\S]*?)><\/p>/g,'<figure><img $1></figure>');
body=body.replace(/href="(https?:[^"]+)"/g,'href="$1" target="_blank" rel="noopener noreferrer"');
const toc=headings.filter(x=>x.level>1).map(x=>'<a class="toc-level-'+x.level+'" href="#'+x.id+'">'+x.text+'</a>').join('\n');
const css=await fs.readFile(path.join(here,'translation.css'),'utf8');
const js=await fs.readFile(path.join(here,'translation.js'),'utf8');
const html='<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>MIPI DSI LCD 상세 가이드 — 전체 한국어 번역</title><style>'+css+'</style></head><body><div class="topbar" id="progress"></div><div class="layout"><aside><div class="brand">MIPI · PROTOCOL STUDY</div><h2>전체 번역과 검증 해설</h2><div class="tools"><button onclick="window.print()">인쇄 / PDF 저장</button><a class="download" href="full_translation_ko.md" download>Markdown</a></div><p class="readme">2026-10-22 · 그림 10개 포함<br>그림을 누르면 원래 크기로 확대합니다.<br>본문 검색: Ctrl+F</p><nav>'+toc+'</nav></aside><main>'+body+'</main></div><dialog id="zoom"><button id="closeZoom">닫기</button><img alt=""></dialog><script>'+js+'</script></body></html>';
await fs.writeFile(path.join(here,'full_translation_ko.html'),html);
console.log(JSON.stringify({markdown_characters:md.length,html_bytes:Buffer.byteLength(html),embedded_images:10,toc_entries:headings.length}));
