#!/usr/bin/env python3
"""Publisher HTTPS; token from environment, no redirect, explicit --send."""
import argparse,json,os,re,sys,urllib.request,urllib.error,urllib.parse
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):return None
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('topic');p.add_argument('--title',default='Hefesto');p.add_argument('--priority',type=int,choices=range(1,6),default=3)
    p.add_argument('--send',action='store_true');a=p.parse_args()
    base=os.environ.get('NTFY_URL','').rstrip('/');u=urllib.parse.urlsplit(base)
    if u.scheme!='https' or not u.hostname or u.username or u.password or u.query or u.fragment or u.path not in ('','/'):
        p.error('NTFY_URL debe ser origen HTTPS, sin credenciales ni ruta')
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,64}',a.topic):p.error('Topic inválido')
    message=sys.stdin.read(4097)
    if not message.strip() or len(message.encode())>4096:p.error('Mensaje requerido: máximo 4096 bytes UTF-8')
    payload={'topic':a.topic,'title':a.title,'message':message,'priority':a.priority}
    if not a.send:
        print('Validado. No enviado. Agregar --send para publicar.');return
    token=os.environ.get('NTFY_TOKEN','')
    if not token or any(c.isspace() for c in token):p.error('Configurar NTFY_TOKEN sin espacios')
    req=urllib.request.Request(base+'/',data=json.dumps(payload).encode(),headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'},method='POST')
    try:
        with urllib.request.build_opener(NoRedirect()).open(req,timeout=15) as response:
            result=json.load(response)
        print('Publicado. ID:',result.get('id','sin ID'))
    except urllib.error.HTTPError as e:
        print('Publicación fallida. HTTP',e.code,'; no se reintenta automáticamente.',file=sys.stderr);sys.exit(1)
    except (urllib.error.URLError,TimeoutError,ValueError):
        print('No se pudo confirmar entrega; revisar servidor antes de reintentar.',file=sys.stderr);sys.exit(1)
if __name__=='__main__':main()
