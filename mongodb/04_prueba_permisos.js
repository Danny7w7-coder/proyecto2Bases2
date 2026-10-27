// =====================================================================
//  MONGODB - Script 04: prueba de permisos de usr_api_mobile
//  Ejecutar conectado como usr_api_mobile:
//   mongosh -u usr_api_mobile -p Api_Mobile2026 --authenticationDatabase reportes_medicos reportes_medicos 04_prueba_permisos.js
// =====================================================================
db = db.getSiblingDB("reportes_medicos");

print("Lectura permitida (resumen_paciente):");
printjson(db.resumen_paciente.findOne({}, { _id: 0 }));

print("\nLectura NO permitida (resultados_estudios):");
try {
  db.resultados_estudios.findOne();
} catch (e) {
  print("  -> Error esperado: " + e.codeName);
}

print("\nEscritura NO permitida (insert):");
try {
  db.resumen_paciente.insertOne({ prueba: 1 });
} catch (e) {
  print("  -> Error esperado: " + e.codeName);
}
