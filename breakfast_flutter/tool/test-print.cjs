// Renderer regression checks without a browser dependency, also run in CI.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const renderer = fs.readFileSync(`${__dirname}/../assets/print/render.js`, 'utf8');
const line = (categoryId, name, qty) => ({categoryId, name, qty, categoryName:categoryId, categoryColor:0});
const data = {
  categories:[{id:'bread',name:'Bread',color:0},{id:'fresh',name:'Fresh',color:2}],
  orders:[
    {id:'a',room:'1',slot:'07:00–07:30',lines:[line('bread','Roll',2),line('fresh','Roll',1)]},
    {id:'b',room:'2',slot:'07:30–08:00',lines:[line('bread','Roll',3)]},
  ],
};
function render(mode) {
  const output = {innerHTML:''};
  const payload = JSON.stringify({...data,printMode:mode});
  vm.runInNewContext(renderer, {
    document:{getElementById:id=>id==='order-data'?{textContent:payload}:output,querySelector:()=>null},
    alert:message=>{throw Error(message);},
  });
  return output.innerHTML;
}
for(const mode of ['all','timetable','totals']) {
  const html = render(mode);
  assert.ok(!html.includes('totalsgrid'));
  assert.ok(html.includes('<th>Item</th><th class="item-total">Total</th><th>07:00'));
  const rows = [...html.matchAll(/<tr[^>]*><td>([\s\S]*?)<\/tr>/g)].map(m=>m[1]);
  assert.equal(rows.length,2,'Same item names in different categories remain separate');
  assert.ok(rows[0].includes('<strong>5</strong></td><td>2</td><td>3</td><td></td>'));
  assert.ok(rows[1].includes('<strong>1</strong></td><td>1</td><td></td>'));
  assert.equal((html.match(/class="timetable"/g)||[]).length,1);
}
const slips = render('orders');
assert.ok(!slips.includes('class="line" style='));
assert.ok(!slips.includes('class="timetable"'));
assert.ok(slips.includes('× 3'));
assert.ok(slips.includes('<h3>1</h3>'));
assert.ok(!slips.includes('<h3>Cabin '));
console.log('Combined timetable totals, blank cells, category grouping, legacy totals mode and unshaded slips passed.');
