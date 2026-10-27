// =====================================================================
//  MONGODB - Script 05: version corta del reporte por medico y tipo
//  (la usa demo.ps1; muestra el resultado como una tabla sencilla)
// =====================================================================
db = db.getSiblingDB("reportes_medicos");

print("MEDICO                       TIPO DE ESTUDIO   CANTIDAD   INGRESOS");
print("---------------------------  ---------------   --------   --------");
db.resultados_estudios.aggregate([
  { $group: { _id: { medico: "$medico", tipo: "$tipo" },
              cantidad: { $sum: 1 }, ingresos: { $sum: "$costo" } } },
  { $sort: { "_id.medico": 1, "_id.tipo": 1 } }
]).forEach(r => print(
  r._id.medico.padEnd(29) + r._id.tipo.padEnd(18) +
  String(r.cantidad).padStart(8) + String(r.ingresos).padStart(11)));
