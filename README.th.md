# ฐานข้อมูลจองตั๋วโรงภาพยนตร์

ฐานข้อมูลโรงภาพยนตร์ 57 ตาราง (หนัง สาขา รอบฉาย ที่นั่ง ราคาตั๋ว สมาชิก คูปอง การจอง การชำระเงิน แต้มสะสม สินค้า)
ที่ใส่กฎการจองไว้ **ในฐานข้อมูลเอง** ด้วย stored procedure บน **PostgreSQL 16** และมี test อัตโนมัติ 68 ข้อ

เริ่มจากงานกลุ่มวิชา database systems ของมหาวิทยาลัย แบ่งเป็น 2 ขั้น:

1. **ออกแบบบน MySQL** ([design-mysql/](design-mysql/README.md)): 57 ตาราง ข้อมูลตัวอย่าง และ query ใช้งานได้จริงผ่าน phpMyAdmin บน XAMPP
2. **implement บน PostgreSQL** ([sql/](sql/)): ใส่กฎการจองไว้ในฐานข้อมูลด้วย stored procedure พร้อม test และ CI

- เรื่องเล่าของโปรเจกต์ตั้งแต่งานวิชาจนถึง implement (ภาษาอังกฤษ): [docs/project-story.md](docs/project-story.md)
- ภาพรวม วิธีรัน กฎธุรกิจ และข้อจำกัด: [README.md](README.md) (ภาษาอังกฤษ)
- ข้อดีของการใส่กฎไว้ในฐานข้อมูล และเหตุผลที่ใช้ PostgreSQL: [docs/why-postgresql.md](docs/why-postgresql.md)
- อธิบายทีละ procedure: [docs/procedure-walkthrough.md](docs/procedure-walkthrough.md)

รันเร็วๆ (ต้องมี Docker และ client `psql`):

```bash
make test
```
