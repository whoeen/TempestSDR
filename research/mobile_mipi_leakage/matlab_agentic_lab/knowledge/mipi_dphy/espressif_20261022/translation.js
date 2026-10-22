document.querySelectorAll('figure img').forEach(img=>{
 const cap=document.createElement('figcaption');cap.textContent=img.alt;img.parentElement.appendChild(cap);
 img.addEventListener('click',()=>{const d=document.querySelector('#zoom');d.querySelector('img').src=img.src;d.querySelector('img').alt=img.alt;d.showModal();});
});
document.querySelector('#closeZoom').onclick=()=>document.querySelector('#zoom').close();
document.querySelector('#zoom').addEventListener('click',e=>{if(e.target===e.currentTarget)e.currentTarget.close()});
function progress(){const max=document.documentElement.scrollHeight-innerHeight;document.querySelector('#progress').style.width=(max>0?scrollY/max*100:0)+'%'}
addEventListener('scroll',progress,{passive:true});progress();