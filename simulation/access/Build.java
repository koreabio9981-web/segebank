import com.healthmarketscience.jackcess.*;
import java.io.*; import java.nio.charset.StandardCharsets; import java.nio.file.*; import java.util.*;
public class Build {
  public static void main(String[] a) throws Exception {
    File out = new File(a[1]); out.delete();
    try (Database db = DatabaseBuilder.create(Database.FileFormat.V2010, out)) {
      String[] order = {"안내","입력","직급표","월간결과","바이너리계수","민감도","개인수당예시","쿼리SQL"};
      for (String name : order) {
        List<String> lines = Files.readAllLines(Paths.get(a[0], name + ".tsv"), StandardCharsets.UTF_8);
        String[] hdr = lines.get(0).split("\t", -1);
        TableBuilder tb = new TableBuilder(name);
        DataType[] types = new DataType[hdr.length];
        for (int i = 0; i < hdr.length; i++) {
          String[] p = hdr[i].split(":"); types[i] = DataType.valueOf(p[1]);
          tb.addColumn(new ColumnBuilder(p[0], types[i]));
        }
        Table t = tb.toTable(db);
        for (String line : lines.subList(1, lines.size())) {
          if (line.isEmpty()) continue;
          String[] v = line.split("\t", -1); Object[] row = new Object[hdr.length];
          for (int i = 0; i < hdr.length; i++) {
            String s = i < v.length ? v[i] : "";
            if (s.isEmpty() || s.equals("None")) { row[i] = null; continue; }
            switch (types[i]) {
              case LONG: row[i] = (int) Math.round(Double.parseDouble(s)); break;
              case DOUBLE: row[i] = Double.parseDouble(s); break;
              default: row[i] = s;
            }
          }
          t.addRow(row);
        }
        System.out.println(name + " rows=" + t.getRowCount());
      }
    }
  }
}
