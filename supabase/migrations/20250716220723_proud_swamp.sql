-- Actualización de base de datos para sistema de impuestos flexible
-- Ejecutar este script en phpMyAdmin después del script principal

-- Verificar si la tabla ya existe, si no, crearla
CREATE TABLE IF NOT EXISTS configuracion_impuestos (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    nombre VARCHAR(50) NOT NULL,
    porcentaje DECIMAL(5,2) NOT NULL,
    activo BOOLEAN DEFAULT TRUE,
    aplicar_por_defecto BOOLEAN DEFAULT FALSE,
    descripcion VARCHAR(200),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Insertar configuración inicial de IGV (flexible para la selva)
INSERT INTO configuracion_impuestos (nombre, porcentaje, activo, aplicar_por_defecto, descripcion) VALUES 
('IGV', 0.00, FALSE, TRUE, 'Impuesto General a las Ventas - Configurado para región de la selva (exonerado)')
ON DUPLICATE KEY UPDATE 
porcentaje = VALUES(porcentaje),
activo = VALUES(activo),
descripcion = VALUES(descripcion);

-- Insertar otras opciones de IGV comunes
INSERT INTO configuracion_impuestos (nombre, porcentaje, activo, aplicar_por_defecto, descripcion) VALUES 
('IGV_ESTANDAR', 18.00, FALSE, FALSE, 'IGV estándar del 18% para otras regiones del Perú'),
('ISC', 0.00, FALSE, FALSE, 'Impuesto Selectivo al Consumo'),
('IMPUESTO_MUNICIPAL', 0.00, FALSE, FALSE, 'Impuesto Municipal Local')
ON DUPLICATE KEY UPDATE descripcion = VALUES(descripcion);

-- Crear índices para mejor rendimiento
CREATE INDEX IF NOT EXISTS idx_impuestos_activo ON configuracion_impuestos(activo);
CREATE INDEX IF NOT EXISTS idx_impuestos_por_defecto ON configuracion_impuestos(aplicar_por_defecto);
CREATE INDEX IF NOT EXISTS idx_impuestos_nombre ON configuracion_impuestos(nombre);

-- Actualizar tabla de ventas para incluir información de impuestos aplicados
ALTER TABLE ventas 
ADD COLUMN IF NOT EXISTS impuesto_aplicado VARCHAR(50) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS porcentaje_impuesto DECIMAL(5,2) DEFAULT 0.00;

-- Crear tabla para historial de cambios de impuestos (auditoría)
CREATE TABLE IF NOT EXISTS historial_impuestos (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    impuesto_id BIGINT NOT NULL,
    accion ENUM('CREADO', 'MODIFICADO', 'ACTIVADO', 'DESACTIVADO') NOT NULL,
    porcentaje_anterior DECIMAL(5,2),
    porcentaje_nuevo DECIMAL(5,2),
    usuario_id BIGINT,
    fecha_cambio TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    observaciones TEXT,
    FOREIGN KEY (impuesto_id) REFERENCES configuracion_impuestos(id),
    FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
);

-- Trigger para registrar cambios en impuestos
DELIMITER //
CREATE TRIGGER IF NOT EXISTS after_update_impuestos
AFTER UPDATE ON configuracion_impuestos
FOR EACH ROW
BEGIN
    IF OLD.porcentaje != NEW.porcentaje THEN
        INSERT INTO historial_impuestos (impuesto_id, accion, porcentaje_anterior, porcentaje_nuevo, observaciones)
        VALUES (NEW.id, 'MODIFICADO', OLD.porcentaje, NEW.porcentaje, 
                CONCAT('Porcentaje cambiado de ', OLD.porcentaje, '% a ', NEW.porcentaje, '%'));
    END IF;
    
    IF OLD.activo != NEW.activo THEN
        INSERT INTO historial_impuestos (impuesto_id, accion, observaciones)
        VALUES (NEW.id, IF(NEW.activo, 'ACTIVADO', 'DESACTIVADO'), 
                CONCAT('Impuesto ', IF(NEW.activo, 'activado', 'desactivado')));
    END IF;
END//
DELIMITER ;

-- Vista para consultar configuración actual de impuestos
CREATE OR REPLACE VIEW vista_impuestos_activos AS
SELECT 
    id,
    nombre,
    porcentaje,
    activo,
    aplicar_por_defecto,
    descripcion,
    created_at,
    updated_at,
    CASE 
        WHEN activo = TRUE AND aplicar_por_defecto = TRUE THEN 'ACTIVO_POR_DEFECTO'
        WHEN activo = TRUE THEN 'ACTIVO'
        ELSE 'INACTIVO'
    END as estado_display
FROM configuracion_impuestos
ORDER BY aplicar_por_defecto DESC, activo DESC, nombre ASC;

-- Función para obtener el impuesto por defecto
DELIMITER //
CREATE FUNCTION IF NOT EXISTS obtener_impuesto_por_defecto() 
RETURNS DECIMAL(5,2)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE porcentaje_default DECIMAL(5,2) DEFAULT 0.00;
    
    SELECT porcentaje INTO porcentaje_default
    FROM configuracion_impuestos 
    WHERE activo = TRUE AND aplicar_por_defecto = TRUE
    LIMIT 1;
    
    RETURN COALESCE(porcentaje_default, 0.00);
END//
DELIMITER ;

-- Insertar configuración inicial para diferentes regiones del Perú
INSERT INTO configuracion_impuestos (nombre, porcentaje, activo, aplicar_por_defecto, descripcion) VALUES 
('IGV_SELVA', 0.00, TRUE, TRUE, 'IGV para región de la selva - Exonerado según normativa'),
('IGV_COSTA_SIERRA', 18.00, FALSE, FALSE, 'IGV estándar para costa y sierra del Perú')
ON DUPLICATE KEY UPDATE 
activo = VALUES(activo),
aplicar_por_defecto = VALUES(aplicar_por_defecto);