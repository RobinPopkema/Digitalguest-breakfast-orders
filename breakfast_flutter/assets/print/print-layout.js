/* Run in the isolated browser print document after fonts have loaded. */
function paginateOrderSlips() {
  const root = document.getElementById('printArea');
  const orderPages = [...root.querySelectorAll('.printpage')].filter(page => page.querySelector('.printgrid'));
  if (!orderPages.length) return;
  const originals = orderPages.flatMap(page => [...page.querySelector('.printgrid').children]);
  const anchor = document.createComment('order slips');
  orderPages[0].before(anchor);
  orderPages.forEach(page => page.remove());
  let grid, columnCount = 4;
  function column(original, continued) {
    if (columnCount === 4) {
      const page = document.createElement('section');
      page.className = 'printpage';
      grid = document.createElement('div');
      grid.className = 'printgrid';
      page.append(grid);
      anchor.before(page);
      columnCount = 0;
    }
    const slip = original.cloneNode(false);
    grid.append(slip);
    columnCount++;
    for (const child of original.children) {
      if (child.tagName === 'H3' || child.classList.contains('time')) {
        const header = child.cloneNode(true);
        if (continued && header.tagName === 'H3') {
          const label = document.createElement('small');
          label.className = 'continuation';
          label.textContent = ' · continued';
          header.append(label);
        }
        slip.append(header);
      }
    }
    if (slip.scrollHeight > slip.clientHeight + 1) throw new Error('An order heading is too large to fit on a slip. Shorten the room number.');
    return slip;
  }
  function overflows(slip) {
    const style = getComputedStyle(slip);
    const bottom = slip.getBoundingClientRect().bottom - parseFloat(style.paddingBottom) - parseFloat(style.borderBottomWidth);
    return slip.scrollHeight > slip.clientHeight + 1 || [...slip.children].some(child => child.getBoundingClientRect().bottom > bottom + 1);
  }
  function splitNode(node, count) {
    const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
    let text, remaining = count;
    while ((text = walker.nextNode())) {
      if (remaining <= text.length) break;
      remaining -= text.length;
    }
    if (!text) throw new Error('Cannot split oversized print content.');
    const prefixRange = document.createRange();
    prefixRange.selectNodeContents(node);
    prefixRange.setEnd(text, remaining);
    const suffixRange = document.createRange();
    suffixRange.selectNodeContents(node);
    suffixRange.setStart(text, remaining);
    const prefix = node.cloneNode(false), suffix = node.cloneNode(false);
    prefix.append(prefixRange.cloneContents());
    suffix.append(suffixRange.cloneContents());
    return [prefix, suffix];
  }
  for (const original of originals) {
    const slips = [];
    const nextSlip = continued => { const slip = column(original, continued); slips.push(slip); return slip; };
    let slip = nextSlip(false), bodyCount = 0;
    const body = [...original.children].filter(child => child.tagName !== 'H3' && !child.classList.contains('time'));
    for (const source of body) {
      let node = source.cloneNode(true);
      while (node) {
        slip.append(node);
        if (!overflows(slip)) { bodyCount++; break; }
        node.remove();
        if (bodyCount) { slip = nextSlip(true); bodyCount = 0; continue; }
        // A single very long item or comment also needs splitting; retain its markup.
        let low = 1, high = node.textContent.length - 1, fit = 0;
        while (low <= high) {
          const mid = Math.floor((low + high) / 2);
          const [prefix] = splitNode(node, mid);
          slip.append(prefix);
          const fits = !overflows(slip);
          prefix.remove();
          if (fits) { fit = mid; low = mid + 1; } else high = mid - 1;
        }
        if (!fit) throw new Error('An item cannot fit on a slip. Shorten the item name or comment.');
        // Prefer a nearby word boundary without discarding whitespace or text.
        const text = node.textContent;
        const boundary = text.lastIndexOf(' ', fit - 1);
        if (boundary > 0 && fit - boundary < 35) fit = boundary + 1;
        if (fit > 0 && /[\uD800-\uDBFF]/.test(text[fit - 1])) fit--;
        const [prefix, suffix] = splitNode(node, fit);
        slip.append(prefix);
        node = suffix;
        slip = nextSlip(true);
        bodyCount = 0;
      }
    }
    if (slips.length > 1 && !original.classList.contains('schedulecard')) {
      slips.forEach((part, i) => {const footer = document.createElement('footer'); footer.className = 'slip-warning'; footer.textContent = `Order has ${slips.length} slips — collect all · ${i + 1}/${slips.length}`; part.append(footer);});
    }
  }
  anchor.remove();
}

function paginateTimetable() {
  const root = document.getElementById('printArea');
  const pages = [...root.querySelectorAll('.printpage')].filter(page => page.querySelector('.timetable'));
  if (!pages.length) return;
  const rows = pages.flatMap(page => [...page.querySelectorAll('.timetable tbody > tr')]);
  const header = pages[0].querySelector('.timetable thead').cloneNode(true);
  const anchor = document.createComment('timetable');
  pages[0].before(anchor);
  pages.forEach(page => page.remove());
  const groups = [];
  for (const row of rows) {
    if (row.classList.contains('timetable-category')) groups.push({header: row, rows: []});
    else {
      if (!groups.length) groups.push({header: null, rows: []});
      groups.at(-1).rows.push(row);
    }
  }
  let column, tbody, itemCount = 0;
  function nextPage() {
    const page = document.createElement('section');
    page.className = 'printpage summarypage pivotpage';
    column = document.createElement('div');
    column.className = 'timetablecolumn';
    const table = document.createElement('table');
    table.className = 'timetable';
    tbody = document.createElement('tbody');
    table.append(header.cloneNode(true), tbody);
    column.append(table);
    page.append(column);
    anchor.before(page);
    itemCount = 0;
  }
  const overflows = () => column.scrollHeight > column.clientHeight + 1;
  nextPage();
  for (const group of groups) {
    let band = group.header?.cloneNode(true);
    if (band) tbody.append(band);
    for (let i = 0; i < group.rows.length; i++) {
      const row = group.rows[i].cloneNode(true);
      tbody.append(row);
      if (overflows()) {
        row.remove();
        if (i === 0) band?.remove();
        if (!itemCount) throw new Error('A timetable item is too tall to fit on a page. Shorten its name.');
        nextPage();
        band = group.header?.cloneNode(true);
        if (band) tbody.append(band);
        tbody.append(row);
        if (overflows()) throw new Error('A timetable item is too tall to fit on a page. Shorten its name.');
      }
      itemCount++;
    }
  }
  anchor.remove();
}
