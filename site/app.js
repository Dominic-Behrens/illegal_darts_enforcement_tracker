(() => {
  'use strict';

  const $ = (id) => document.getElementById(id);
  const status = $('status');
  const dashboard = $('dashboard');
  const councilSelect = $('council-select');
  const snapshotSelect = $('snapshot-select');
  const search = $('location-search');
  const svgNS = 'http://www.w3.org/2000/svg';
  const dateFormatter = new Intl.DateTimeFormat('en-AU', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' });
  const updatedFormatter = new Intl.DateTimeFormat('en-AU', {
    day: 'numeric', month: 'short', year: 'numeric', hour: 'numeric', minute: '2-digit',
    timeZone: 'Australia/Sydney', timeZoneName: 'short'
  });
  let observations = [];
  let changes = [];
  let dates = [];
  let sourceMode = 'tracker';
  let captures = new Map();
  let map = null;
  let markerLayer = null;
  let currentMarkers = false;

  function text(element, value) {
    element.textContent = value;
    return element;
  }

  function node(tag, className, value) {
    const element = document.createElement(tag);
    if (className) element.className = className;
    if (value !== undefined) text(element, value);
    return element;
  }

  function svgNode(tag, attributes = {}, value) {
    const element = document.createElementNS(svgNS, tag);
    for (const [name, attribute] of Object.entries(attributes)) element.setAttribute(name, String(attribute));
    if (value !== undefined) text(element, value);
    return element;
  }

  function formatDate(value) {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return value || 'Not published';
    const date = new Date(`${value}T12:00:00Z`);
    return Number.isNaN(date.getTime()) ? value : dateFormatter.format(date);
  }

  function councilOf(row) {
    return typeof row.council === 'string' && row.council.trim() ? row.council.trim() : 'Council not published';
  }

  function coordinates(row) {
    if (row.latitude === null || row.latitude === undefined || row.longitude === null || row.longitude === undefined || row.latitude === '' || row.longitude === '') return null;
    const lat = Number(row.latitude);
    const lng = Number(row.longitude);
    return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 ? [lat, lng] : null;
  }

  function chosenRows(date) {
    return observations.filter((row) => row.snapshot_date === date && (!councilSelect.value || councilOf(row) === councilSelect.value));
  }

  function newObservations(date) {
    if (date === dates[0]) return 0;
    return changes.filter((row) => row.snapshot_date === date && row.change_type === 'added' && row.is_initial_snapshot === false && (!councilSelect.value || councilOf(row) === councilSelect.value)).length;
  }

  function selectDate(date) {
    snapshotSelect.value = date;
    render();
  }

  function captureUrl(date) {
    const url = captures.get(date)?.url;
    if (typeof url !== 'string') return null;
    try {
      const parsed = new URL(url);
      return parsed.protocol === 'https:' ? parsed.href : null;
    } catch {
      return null;
    }
  }

  function drawChart() {
    const chart = $('trend-chart');
    chart.replaceChildren();
    const width = Math.max(740, dates.length * (sourceMode === 'archived_preview' ? 86 : 31) + 84);
    const height = 286;
    const left = 43, right = width - 22, top = 18, bottom = 224;
    const archived = sourceMode === 'archived_preview';
    const data = dates.map((date) => ({ date, listed: chosenRows(date).length, added: archived ? 0 : newObservations(date) }));
    const maxListed = Math.max(1, ...data.map((d) => d.listed));
    const maxAdded = archived ? 1 : Math.max(1, ...data.map((d) => d.added));
    const firstTime = Date.parse(`${dates[0]}T00:00:00Z`);
    const lastTime = Date.parse(`${dates[dates.length - 1]}T00:00:00Z`);
    const x = (index) => left + (archived
      ? (firstTime === lastTime ? (right - left) / 2 : (Date.parse(`${data[index].date}T00:00:00Z`) - firstTime) * (right - left) / (lastTime - firstTime))
      : (data.length === 1 ? (right - left) / 2 : index * (right - left) / (data.length - 1)));
    const y = (value) => bottom - (value / maxListed) * (bottom - top);
    chart.setAttribute('viewBox', `0 0 ${width} ${height}`);
    chart.setAttribute('width', width);
    chart.setAttribute('height', height);
    chart.setAttribute('aria-label', archived
      ? `Listed orders at sparse archived capture dates, ${councilSelect.value || 'all councils'}. Dates between captures are unknown. The accompanying table contains exact values.`
      : `Orders listed and first observed by snapshot, ${councilSelect.value || 'all councils'}. The accompanying table contains exact values.`);
    $('chart-wrap').style.setProperty('--chart-width', `${width}px`);

    for (let i = 0; i <= 4; i++) {
      const value = Math.round(maxListed * i / 4);
      const yy = y(maxListed * i / 4);
      chart.append(svgNode('line', { x1: left, y1: yy, x2: right, y2: yy, class: 'grid-line' }));
      chart.append(svgNode('text', { x: left - 11, y: yy + 4, 'text-anchor': 'end', class: 'axis-label' }, String(value)));
    }
    if (!archived) {
      for (let i = 0; i < data.length; i++) {
        const point = data[i];
        const xx = x(i);
        const barHeight = point.added / maxAdded * 44;
        chart.append(svgNode('rect', { x: xx - 5, y: bottom - barHeight, width: 10, height: Math.max(barHeight, point.added ? 2 : 0), rx: 2, class: 'event-bar' }));
      }
      const path = data.map((point, index) => `${index ? 'L' : 'M'} ${x(index)} ${y(point.listed)}`).join(' ');
      chart.append(svgNode('path', { d: path, class: 'trend-line' }));
    }
    const labelEvery = Math.max(1, Math.ceil(data.length / Math.max(2, width / 110)));
    let lastLabelX = -Infinity;
    data.forEach((point, index) => {
      const xx = x(index);
      const yy = y(point.listed);
      const selected = point.date === snapshotSelect.value;
      chart.append(svgNode('circle', { cx: xx, cy: yy, r: archived ? (selected ? 7 : 5) : (selected ? 6 : 3.5), class: selected ? 'trend-point selected' : 'trend-point' }));
      const hit = svgNode('circle', { cx: xx, cy: yy, r: 12, class: 'point-hit', tabindex: 0, role: 'button', 'aria-label': archived ? `${formatDate(point.date)}: ${point.listed} listed in archived capture. Select date.` : `${formatDate(point.date)}: ${point.listed} listed, ${point.added} first observed. Select snapshot.`, 'aria-pressed': String(selected) });
      hit.addEventListener('click', () => selectDate(point.date));
      hit.addEventListener('keydown', (event) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          selectDate(point.date);
        }
      });
      chart.append(hit);
      if ((archived ? xx - lastLabelX >= 125 : index % labelEvery === 0 || index === data.length - 1)) {
        chart.append(svgNode('text', { x: xx, y: bottom + 27, 'text-anchor': 'middle', class: 'axis-label date-axis' }, archived ? formatDate(point.date) : formatDate(point.date).replace(/ \d{4}$/, '')));
        lastLabelX = xx;
      }
    });
    const rows = $('trend-rows');
    rows.replaceChildren();
    for (const point of data) {
      const tr = node('tr');
      const date = node('th');
      date.scope = 'row';
      const sourceUrl = archived ? captureUrl(point.date) : null;
      if (sourceUrl) {
        const link = node('a', null, formatDate(point.date));
        link.href = sourceUrl;
        link.target = '_blank';
        link.rel = 'noopener noreferrer';
        date.append(link);
      } else {
        text(date, formatDate(point.date));
      }
      tr.append(date, node('td', null, String(point.listed)));
      if (!archived) tr.append(node('td', null, String(point.added)));
      rows.append(tr);
    }
  }

  function popupContent(row) {
    const content = node('div', 'popup-content');
    content.append(node('strong', null, row.premise_name || 'Unnamed premise'));
    content.append(node('span', null, row.address || 'Address not published'));
    content.append(node('span', null, councilOf(row)));
    if (row.closure_order_type) content.append(node('span', null, row.closure_order_type));
    content.append(node('small', null, `Commenced: ${formatDate(row.date_commenced)} · Conclusion: ${formatDate(row.conclusion_date)}`));
    return content;
  }

  function renderMap(rows) {
    const fallback = $('map-fallback');
    const located = rows.filter((row) => coordinates(row));
    $('map-caption').textContent = `${located.length} of ${rows.length} listed ${rows.length === 1 ? 'order has' : 'orders have'} published coordinates. Map markers do not indicate exact premises where coordinates are absent or inaccurate.`;
    if (!window.L) {
      fallback.hidden = false;
      $('map').hidden = true;
      return false;
    }
    try {
      if (!map) {
        map = L.map('map', { scrollWheelZoom: false }).setView([-32.8, 147.2], 6);
        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
          attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors', maxZoom: 18
        }).addTo(map);
        markerLayer = L.layerGroup().addTo(map);
      }
      markerLayer.clearLayers();
      const bounds = [];
      const markers = new Map();
      for (const row of located) {
        const point = coordinates(row);
        bounds.push(point);
        const marker = L.circleMarker(point, { radius: 7, color: '#fffefa', weight: 1.5, fillColor: '#315e56', fillOpacity: 0.95 }).bindPopup(popupContent(row));
        markerLayer.addLayer(marker);
        markers.set(row, marker);
      }
      if (bounds.length === 1) map.setView(bounds[0], 12);
      else if (bounds.length) map.fitBounds(bounds, { padding: [35, 35], maxZoom: 12 });
      else map.setView([-32.8, 147.2], 6);
      requestAnimationFrame(() => map.invalidateSize());
      fallback.hidden = true;
      $('map').hidden = false;
      return markers;
    } catch (error) {
      fallback.hidden = false;
      $('map').hidden = true;
      return false;
    }
  }

  function renderList(rows, markers) {
    const query = search.value.trim().toLocaleLowerCase();
    const visible = rows.filter((row) => [row.premise_name, row.address, councilOf(row)].some((value) => String(value || '').toLocaleLowerCase().includes(query)));
    $('list-count').textContent = `${visible.length} of ${rows.length} ${rows.length === 1 ? 'location' : 'locations'} shown`;
    const list = $('location-list');
    list.replaceChildren();
    if (!visible.length) {
      list.append(node('li', 'list-empty', rows.length ? 'No locations match your search.' : 'No orders listed for this snapshot and council.'));
      return;
    }
    for (const row of visible) {
      const item = node('li', 'location-item');
      const title = node('h3', null, row.premise_name || 'Unnamed premise');
      item.append(title, node('p', 'address', row.address || 'Address not published'));
      item.append(node('p', 'location-meta', `${councilOf(row)} · ${row.closure_order_type || 'Type not published'}`));
      const detail = node('p', 'date-meta', `Commenced ${formatDate(row.date_commenced)} · Conclusion ${formatDate(row.conclusion_date)}`);
      item.append(detail);
      if (markers && markers.has(row)) {
        const button = node('button', 'map-link', 'Show on map');
        button.type = 'button';
        button.addEventListener('click', () => {
          const marker = markers.get(row);
          map.setView(marker.getLatLng(), Math.max(map.getZoom(), 12));
          marker.openPopup();
          $('map').scrollIntoView({ behavior: 'smooth', block: 'center' });
        });
        item.append(button);
      }
      list.append(item);
    }
  }

  function render() {
    const date = snapshotSelect.value;
    const rows = chosenRows(date);
    $('active-count').textContent = rows.length.toLocaleString('en-AU');
    if (sourceMode !== 'live_preview') {
      if (sourceMode === 'tracker') {
        $('new-count').textContent = newObservations(date).toLocaleString('en-AU');
        $('new-scope').textContent = councilSelect.value ? ` in ${councilSelect.value}` : '';
      }
      $('snapshot-count').textContent = dates.length.toLocaleString('en-AU');
      drawChart();
    }
    $('active-scope').textContent = ` on ${formatDate(date)}${councilSelect.value ? ` in ${councilSelect.value}` : ''}`;
    $('summary-context').textContent = sourceMode === 'live_preview'
      ? `Published register download of ${formatDate(date)}${councilSelect.value ? ` · ${councilSelect.value}` : ' · all councils'}.`
      : `${sourceMode === 'archived_preview' ? 'Observed capture' : 'Snapshot'} of ${formatDate(date)}${councilSelect.value ? ` · ${councilSelect.value}` : ' · all councils'}.`;
    $('location-context').textContent = `Showing ${sourceMode === 'live_preview' ? 'the register download' : sourceMode === 'archived_preview' ? 'the observed capture' : 'the snapshot'} of ${formatDate(date)}${councilSelect.value ? ` · ${councilSelect.value}` : ' · all councils'}. Map markers use published coordinates only.`;
    if (sourceMode === 'archived_preview') {
      const capture = captures.get(date);
      const sourceUrl = captureUrl(date);
      const link = $('capture-link');
      link.textContent = capture?.source || 'Source capture';
      if (sourceUrl) link.href = sourceUrl;
      else link.removeAttribute('href');
      $('selection-note').textContent = `Selected observed capture: ${formatDate(date)}. Other dates are unknown.`;
    }
    currentMarkers = renderMap(rows);
    renderList(rows, currentMarkers);
  }

  async function load() {
    try {
      const response = await fetch('./data/dashboard.json');
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      if (!Array.isArray(data.observations) || !Array.isArray(data.changes)) throw new Error('Invalid dashboard data');
      sourceMode = data.source_mode === 'live_preview' || data.source_mode === 'archived_preview' ? data.source_mode : 'tracker';
      observations = data.observations;
      changes = data.changes;
      if (sourceMode === 'archived_preview') {
        if (!Array.isArray(data.captures)) throw new Error('Invalid archived capture data');
        captures = new Map(data.captures.filter((capture) => capture && typeof capture.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(capture.date)).map((capture) => [capture.date, capture]));
        dates = [...captures.keys()].sort();
      } else {
        dates = [...new Set([...observations, ...changes].map((row) => row.snapshot_date).filter((date) => typeof date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(date)))].sort();
      }
      if (!dates.length) {
        status.textContent = 'No accepted observations are available yet. Please check back after the first snapshot.';
        status.classList.add('status-empty');
        return;
      }
      const councils = [...new Set((sourceMode === 'archived_preview' ? observations : [...observations, ...changes]).map(councilOf))].sort((a, b) => a.localeCompare(b));
      for (const council of councils) {
        const option = node('option', null, council);
        option.value = council;
        councilSelect.append(option);
      }
      const archived = sourceMode === 'archived_preview';
      const live = sourceMode === 'live_preview';
      if (archived) $('snapshot-control').querySelector('label').textContent = 'Capture date';
      for (const date of [...dates].reverse()) {
        const option = node('option', null, formatDate(date));
        option.value = date;
        snapshotSelect.append(option);
      }
      snapshotSelect.value = dates[dates.length - 1];
      $('preview-notice').hidden = !live;
      $('archive-notice').hidden = !archived;
      $('snapshot-control').hidden = live;
      $('trend-section').hidden = live;
      $('trend-section').classList.toggle('archive-mode', archived);
      $('first-observed-metric').hidden = live || archived;
      $('first-observed-legend').hidden = archived;
      $('first-observed-column').hidden = archived;
      $('snapshot-metric').hidden = live;
      $('tracker-note').hidden = live || archived;
      $('preview-note').hidden = !live;
      $('archive-note').hidden = !archived;
      $('capture-source').hidden = !archived;
      $('metrics').classList.toggle('preview', live);
      $('metrics').classList.toggle('archived', archived);
      if (archived) {
        $('snapshot-label').textContent = 'Captures shown';
        $('snapshot-explanation').textContent = 'Available archived copies and the latest live CSV; missing dates are unknown.';
        $('trend-title').textContent = 'Observed captures';
        $('trend-description').textContent = 'Listed orders only at available archive capture dates and the live download. Dots mark observations; gaps are unknown. Select a dot to inspect that date.';
        $('trend-caption').textContent = 'Listed orders at observed capture dates for the selected council; dates link to their source';
      }
      $('selection-note').textContent = live ? `Register downloaded ${formatDate(snapshotSelect.value)}` : archived ? '' : 'Select a snapshot to see the register as recorded on that date.';
      if (data.generated_at) {
        const updated = new Date(data.generated_at);
        $('updated-at').textContent = Number.isNaN(updated.getTime()) ? '' : `Data prepared ${updatedFormatter.format(updated)}`;
      }
      status.hidden = true;
      dashboard.hidden = false;
      councilSelect.addEventListener('change', render);
      snapshotSelect.addEventListener('change', render);
      search.addEventListener('input', () => renderList(chosenRows(snapshotSelect.value), currentMarkers));
      render();
    } catch (error) {
      status.textContent = 'Dashboard data could not be loaded. Please try again later or consult the official register.';
      status.classList.add('status-empty');
    }
  }

  load();
})();
