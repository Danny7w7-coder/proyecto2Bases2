// =====================================================================
//  MONGODB - Script 06: reporte por medico y tipo de estudio en JSON
//  (lo usa reporte.ps1 para dibujarlo como tabla en la pagina web)
// =====================================================================
db = db.getSiblingDB("reportes_medicos");

const filas = db.resultados_estudios.aggregate([
  { $group: { _id: { medico: "$medico", tipo: "$tipo" },
              cantidad: { $sum: 1 }, ingresos: { $sum: "$costo" } } },
  { $project: { _id: 0, medico: "$_id.medico", tipo_de_estudio: "$_id.tipo",
                cantidad: 1, ingresos: 1 } },
  { $sort: { medico: 1, tipo_de_estudio: 1 } }
]).toArray();

print(JSON.stringify(filas));
