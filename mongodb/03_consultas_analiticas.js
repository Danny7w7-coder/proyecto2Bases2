// =====================================================================
//  MONGODB - Script 03: consultas analiticas (Operacion requerida #5)
//  Se ejecuta DESPUES de que PostgreSQL exporto los datos con mongo_fdw.
// =====================================================================
db = db.getSiblingDB("reportes_medicos");

print("\n=== Cantidad de documentos recibidos desde PostgreSQL ===");
print("resultados_estudios  : " + db.resultados_estudios.countDocuments());
print("resumen_paciente     : " + db.resumen_paciente.countDocuments());
print("indicadores_mensuales: " + db.indicadores_mensuales.countDocuments());

print("\n=== Ejemplo de documento desnormalizado ===");
printjson(db.resultados_estudios.findOne({}, { _id: 0 }));

// ---------------------------------------------------------------------
// 1) PRODUCTIVIDAD MEDICA: estudios por MEDICO y TIPO DE ESTUDIO
// ---------------------------------------------------------------------
print("\n=== 1) Estudios por medico y tipo de estudio ===");
db.resultados_estudios.aggregate([
  { $group: {
      _id: { medico: "$medico", tipo: "$tipo" },
      cantidad:       { $sum: 1 },
      ingreso_total:  { $sum: "$costo" },
      costo_promedio: { $avg: "$costo" }
  }},
  { $project: {
      _id: 0,
      medico: "$_id.medico",
      tipo: "$_id.tipo",
      cantidad: 1,
      ingreso_total: 1,
      costo_promedio: { $round: ["$costo_promedio", 2] }
  }},
  { $sort: { medico: 1, tipo: 1 } }
]).forEach(printjson);

// ---------------------------------------------------------------------
// 2) RANKING DE MEDICOS (total de estudios y tipos distintos)
// ---------------------------------------------------------------------
print("\n=== 2) Ranking de medicos por cantidad de estudios ===");
db.resultados_estudios.aggregate([
  { $group: {
      _id: "$medico",
      especialidad: { $first: "$especialidad" },
      total_estudios: { $sum: 1 },
      tipos_realizados: { $addToSet: "$tipo" }
  }},
  { $sort: { total_estudios: -1 } }
]).forEach(printjson);

// ---------------------------------------------------------------------
// 3) RENDIMIENTO DE CLINICAS: estudios e ingresos por sucursal
// ---------------------------------------------------------------------
print("\n=== 3) Rendimiento por sucursal ===");
db.resultados_estudios.aggregate([
  { $group: {
      _id: "$sucursal",
      estudios: { $sum: 1 },
      ingresos: { $sum: "$costo" },
      pacientes: { $addToSet: "$id_paciente" }
  }},
  { $project: { _id: 0, sucursal: "$_id", estudios: 1, ingresos: 1,
                pacientes_atendidos: { $size: "$pacientes" } } },
  { $sort: { ingresos: -1 } }
]).forEach(printjson);

// ---------------------------------------------------------------------
// 4) Guardar el reporte por medico/tipo en su propia coleccion ($merge)
// ---------------------------------------------------------------------
db.resultados_estudios.aggregate([
  { $group: { _id: { medico: "$medico", tipo: "$tipo" }, cantidad: { $sum: 1 } } },
  { $merge: { into: "reporte_medico_tipo", whenMatched: "replace", whenNotMatched: "insert" } }
]);
print("\n=== 4) Coleccion reporte_medico_tipo generada: " +
      db.reporte_medico_tipo.countDocuments() + " documentos ===");

// ---------------------------------------------------------------------
// 5) Proyeccion dinamica: solo ultrasonidos, mostrando pocos campos
// ---------------------------------------------------------------------
print("\n=== 5) Ultrasonidos (proyeccion) ===");
db.resultados_estudios.find(
  { tipo: "Ultrasonido" },
  { _id: 0, paciente: 1, medico: 1, fecha: 1, "resultado.hallazgo": 1 }
).sort({ fecha: -1 }).forEach(printjson);

// ---------------------------------------------------------------------
// 6) Indicadores mensuales exportados desde PostgreSQL
// ---------------------------------------------------------------------
print("\n=== 6) Indicadores mensuales ===");
db.indicadores_mensuales.find({}, { _id: 0 }).sort({ mes: 1, sucursal: 1 }).forEach(printjson);
