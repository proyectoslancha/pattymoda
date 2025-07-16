-- Script SQL actualizado para DPattyModa con roles mejorados
-- Ejecutar este script en phpMyAdmin

-- Actualizar tabla de usuarios con nuevos roles
ALTER TABLE usuarios MODIFY COLUMN rol ENUM('SUPER_ADMIN','ADMIN','MANAGER','VENDEDOR','CAJERO','INVENTARIO') NOT NULL;

-- Insertar usuarios con diferentes roles
INSERT INTO usuarios (nombre, email, password, rol, activo) VALUES 
('Super Administrador', 'superadmin@dpattymoda.com', '$2a$10$vG7SV3wo9mS8iGNCwvThrufIYCOloXFaPyV0YAmPF62WQGZosYJz2', 'SUPER_ADMIN', 1),
('Gerente General', 'gerente@dpattymoda.com', '$2a$10$vG7SV3wo9mS8iGNCwvThrufIYCOloXFaPyV0YAmPF62WQGZosYJz2', 'MANAGER', 1),
('Cajero Principal', 'cajero@dpattymoda.com', '$2a$10$vG7SV3wo9mS8iGNCwvThrufIYCOloXFaPyV0YAmPF62WQGZosYJz2', 'CAJERO', 1),
('Encargado Inventario', 'inventario@dpattymoda.com', '$2a$10$vG7SV3wo9mS8iGNCwvThrufIYCOloXFaPyV0YAmPF62WQGZosYJz2', 'INVENTARIO', 1)
ON DUPLICATE KEY UPDATE 
nombre = VALUES(nombre),
rol = VALUES(rol);

-- Crear tabla para facturas/boletas
CREATE TABLE IF NOT EXISTS comprobantes (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    venta_id BIGINT NOT NULL,
    tipo ENUM('BOLETA', 'FACTURA') NOT NULL,
    serie VARCHAR(10) NOT NULL,
    numero VARCHAR(20) NOT NULL,
    fecha_emision TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    subtotal DECIMAL(10,2) NOT NULL,
    igv DECIMAL(10,2) NOT NULL,
    total DECIMAL(10,2) NOT NULL,
    qr_code TEXT,
    estado ENUM('EMITIDA', 'ANULADA') DEFAULT 'EMITIDA',
    hash_validation VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (venta_id) REFERENCES ventas(id) ON DELETE CASCADE,
    UNIQUE KEY unique_comprobante (tipo, serie, numero)
);

-- Crear tabla para métodos de pago múltiples
CREATE TABLE IF NOT EXISTS metodos_pago_venta (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    venta_id BIGINT NOT NULL,
    tipo_pago ENUM('EFECTIVO', 'TARJETA', 'YAPE', 'PLIN', 'TRANSFERENCIA') NOT NULL,
    monto DECIMAL(10,2) NOT NULL,
    referencia VARCHAR(100),
    tipo_tarjeta VARCHAR(50),
    ultimos_4_digitos VARCHAR(4),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (venta_id) REFERENCES ventas(id) ON DELETE CASCADE
);

-- Crear tabla para secuencias de comprobantes
CREATE TABLE IF NOT EXISTS secuencias_comprobantes (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    tipo ENUM('BOLETA', 'FACTURA') NOT NULL,
    serie VARCHAR(10) NOT NULL,
    ultimo_numero INT NOT NULL DEFAULT 0,
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_serie (tipo, serie)
);

-- Insertar secuencias iniciales
INSERT INTO secuencias_comprobantes (tipo, serie, ultimo_numero) VALUES 
('BOLETA', 'B001', 0),
('FACTURA', 'F001', 0)
ON DUPLICATE KEY UPDATE ultimo_numero = ultimo_numero;

-- Crear tabla para configuración de impuestos
CREATE TABLE IF NOT EXISTS configuracion_impuestos (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    nombre VARCHAR(50) NOT NULL,
    porcentaje DECIMAL(5,2) NOT NULL,
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insertar configuración de IGV
INSERT INTO configuracion_impuestos (nombre, porcentaje, activo) VALUES 
('IGV', 18.00, TRUE)
ON DUPLICATE KEY UPDATE porcentaje = VALUES(porcentaje);

-- Actualizar tabla de ventas para incluir más campos
ALTER TABLE ventas 
ADD COLUMN IF NOT EXISTS numero_venta VARCHAR(20) UNIQUE,
ADD COLUMN IF NOT EXISTS tipo_comprobante ENUM('BOLETA', 'FACTURA') DEFAULT 'BOLETA',
ADD COLUMN IF NOT EXISTS ruc_cliente VARCHAR(11),
ADD COLUMN IF NOT EXISTS razon_social VARCHAR(200);

-- Crear índices para mejor rendimiento
CREATE INDEX IF NOT EXISTS idx_ventas_numero ON ventas(numero_venta);
CREATE INDEX IF NOT EXISTS idx_comprobantes_serie_numero ON comprobantes(serie, numero);
CREATE INDEX IF NOT EXISTS idx_metodos_pago_venta ON metodos_pago_venta(venta_id);

-- Crear vista para reportes de ventas
CREATE OR REPLACE VIEW vista_ventas_completas AS
SELECT 
    v.id,
    v.numero_venta,
    v.fecha,
    CONCAT(c.nombre, ' ', c.apellido) as cliente_nombre,
    c.email as cliente_email,
    v.subtotal,
    v.descuento,
    v.impuesto,
    v.precio_total,
    v.estado,
    v.metodo_pago,
    COUNT(dv.id) as total_items,
    SUM(dv.cantidad) as total_productos
FROM ventas v
LEFT JOIN clientes c ON v.cliente_id = c.id
LEFT JOIN detalle_venta dv ON v.id = dv.venta_id
GROUP BY v.id;

-- Crear función para generar número de venta
DELIMITER //
CREATE FUNCTION IF NOT EXISTS generar_numero_venta() 
RETURNS VARCHAR(20)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE nuevo_numero VARCHAR(20);
    DECLARE contador INT;
    
    SELECT COALESCE(MAX(CAST(SUBSTRING(numero_venta, 2) AS UNSIGNED)), 0) + 1 
    INTO contador 
    FROM ventas 
    WHERE numero_venta LIKE 'V%';
    
    SET nuevo_numero = CONCAT('V', LPAD(contador, 8, '0'));
    
    RETURN nuevo_numero;
END//
DELIMITER ;

-- Trigger para asignar número de venta automáticamente
DELIMITER //
CREATE TRIGGER IF NOT EXISTS before_insert_venta
BEFORE INSERT ON ventas
FOR EACH ROW
BEGIN
    IF NEW.numero_venta IS NULL THEN
        SET NEW.numero_venta = generar_numero_venta();
    END IF;
END//
DELIMITER ;