
module read_xlsx_v

import szip
import strconv

struct XLSX {
mut:
  zp szip.Zip
}

fn XLSX.new(zipfile string) !XLSX {
  mut zp := szip.open(zipfile, szip.CompressionLevel.no_compression, szip.OpenMode.read_only)!
  return XLSX{ zp: zp }
}

[unsafe]
fn (mut xlsx XLSX) free() {
  xlsx.zp.close()
}

fn (mut xlsx XLSX) open_xml(name string) !string {
  xlsx.zp.open_entry(name)!
  defer { xlsx.zp.close_entry() }
  size := xlsx.zp.size()
  buf := xlsx.zp.read_entry()!
  xml := unsafe { tos(buf, int(size)) }
  return xml
}

fn (mut xlsx XLSX) parse_shared_strings() ![]string {
  xml := xlsx.open_xml('xl/sharedStrings.xml')!
  tags := XMLParser.new(xml)
  return tags.filter(it.name == 'si').map(it.text())
}

fn r2ci(r string) !int {
  letters := r.trim('0123456789').to_lower()
  mut sum := 0
  for letter in letters.split('') {
    num := strconv.parse_int(letter, 36, 0)!
    sum = sum * 26 + int(num) - 9
  }
  return sum - 1
}

fn (mut xlsx XLSX) parse_sheet(shared_strings []string) ![][]string {
  xml := xlsx.open_xml('xl/worksheets/sheet1.xml')!
  tags := XMLParser.new(xml)
  rows := tags.filter(it.name == 'row')

  mut data := [][]string{cap: rows.len}

  for row in rows {
    cols := row.children
    mut values := []string{len: cols.len}
    for col_i, col in cols {
      ci := if col_r := col.attributes['r'] { r2ci(col_r)! } else { col_i }
      v := col.text() 

      value := if t := col.attributes['t'] {
        match t {
          's' { shared_strings[strconv.parse_int(v, 10, 0)!] or { v }}
          'e' { '' }
          else { v }
        }
      } else {
        v
      }
      if ci >= values.len {
        unsafe {
          values.grow_len(ci - values.len + 1)
        }
      }
      // println('ci=${ci}, v=${v}, value=${value}')
      values[ci] = value
    }
    if values.any(it.trim_space() != '') {
      data << values
    }
  }

  return data 
}

pub fn parse(xlsxfile string) ![][]string {
  mut xlsx := XLSX.new(xlsxfile)!

  shared_strings := xlsx.parse_shared_strings()!

  data := xlsx.parse_sheet(shared_strings)!

  return data
}

