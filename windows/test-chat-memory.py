"""Exercise shared memory logic with an isolated in-memory files service."""
from pathlib import Path
import argparse
from logic_test import runner_arguments, run_checks

parser=argparse.ArgumentParser(description=__doc__)
runner_arguments(parser)
args=parser.parse_args()
source=Path(__file__).resolve().parents[1].joinpath('marea.luau').read_text(encoding='utf-8')
start=source.index('    -- ── her memory ──')
end=source.index('    -- ── the worker ──',start)
checks=r'''
local store, handlers, timers, replies = {}, {}, {}, {}
local fact, text, model, rows = {}, {}, {}, {}
local function copy(value)
    if type(value)~='table' then return value end
    local out={} for k,v in pairs(value) do out[k]=copy(v) end return out
end
local sys={}
sys.ask=function(command,name)
    if command=='files.read' then return copy(store[name]) end
    assert(command=='files.list')
    local names={} for name in pairs(store) do names[#names+1]=name end return names
end
sys.call=function(command,name,value)
    if command=='files.write' then store[name]=copy(value)
    else assert(command=='files.remove');store[name]=nil end
end
local function tr(value) return value end
local function first_letters(s,n) local at=utf8.offset(s,n+1);return at and s:sub(1,at-1) or s end
local function add(kind,value,detail,state) rows[#rows+1]={kind=kind,text=value,detail=detail,state=state};return #rows end
local function finish_row(row,ok) rows[row].state=ok and 1 or 2 end
local function answer(id,ok,value) replies[id]={ok=ok,text=value} end
local function on(name,callback) handlers[name]=callback end
local function after(delay,callback) timers[#timers+1]={delay=delay,run=callback};return #timers end
local function cancel(id) timers[id].cancelled=true end
__MEMORY__
remember('save','memory_save',{text='  Prefiero café y notas en español.  '})
assert(replies.save.ok and store['memory.json'].facts[1].text=='Prefiero café y notas en español.')
local id=store['memory.json'].facts[1].id
remember('duplicate','memory_save',{text='Prefiero café y notas en español.'})
assert(#store['memory.json'].facts==1)
remember('recall','memory_recall',{query='café español'})
assert(replies.recall.ok and replies.recall.text:find(id,1,true))
remember('note','memory_learn',{title='Abrir mis notas',when='Cuando busco apuntes',how='Abre el buscador y escribe notas.'})
remember('replace','memory_learn',{title='Abrir mis notas',when='Al estudiar',how='Busca la carpeta Apuntes.'})
assert(#store['memory.json'].notes==1)
remember('read','memory_read',{title='mis notas'})
assert(replies.read.ok and replies.read.text:find('Busca la carpeta Apuntes.',1,true))
local prompt=for_her()
assert(#prompt.facts==1 and #prompt.notes==1 and prompt.notes[1].how==nil)
remember('forget','memory_forget',{id='['..id..']'})
assert(replies.forget.ok and #store['memory.json'].facts==0)
show_memory();handlers.mem_forget(0)
assert(#store['memory.json'].notes==0)
rows={{kind=1,text='Voy al taller el viernes.'},{kind=2,text='Entendido, al taller el viernes.'},{kind=4,text='pending action'}}
keep_talk()
local names=talks()
assert(#names==1 and #store[names[1]].rows==2)
rows={{kind=1,text='¿Qué dije del taller?'}}
remember('search','memory_search',{query='taller viernes'})
assert(replies.search.ok and replies.search.text:find('Voy al taller el viernes.',1,true))
store['settings.json']={keep=true};store['chat-other.json']={keep=true}
handlers.mem_clear_talks()
assert(fact['mem.sure']==true and #talks()==1)
timers[#timers].run()
assert(fact['mem.sure']==false and #talks()==1)
handlers.mem_clear_talks();handlers.mem_clear_talks()
assert(#talks()==0 and fact['mem.sure']==false and store['settings.json'].keep and store['chat-other.json'].keep)
remember('empty','memory_save',{text=' '});assert(not replies.empty.ok)
remember('unknown','memory_read',{title='Missing'});assert(not replies.unknown.ok)
log('PASS: shared chat memory save, recall, notes, archive, search and confirmed deletion')
'''.replace('__MEMORY__',source[start:end])
run_checks(args,checks,'PASS: shared chat memory','chat-memory')
