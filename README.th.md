# ฐานข้อมูลจองตั๋วโรงภาพยนตร์

ฐานข้อมูลโรงภาพยนตร์ 57 ตาราง (หนัง สาขา รอบฉาย ที่นั่ง ราคาตั๋ว สมาชิก คูปอง การจอง การชำระเงิน แต้มสะสม สินค้า)
ที่ใส่กฎการจองไว้ **ในฐานข้อมูลเอง** ด้วย stored procedure บน **PostgreSQL 16** และมี test อัตโนมัติ 68 ข้อ

เริ่มจากงานกลุ่มวิชา database systems ของมหาวิทยาลัย (ออกแบบ 57 ตารางและนำเสนอในวิชา ด้วย MySQL กับ phpMyAdmin)
repo นี้คืองาน implement ที่ต่อยอดมา: logic, test และ CI บน PostgreSQL

- ภาพรวม วิธีรัน กฎธุรกิจ และข้อจำกัด: [README.md](README.md) (ภาษาอังกฤษ)
- ข้อดีของการใส่กฎไว้ในฐานข้อมูล และเหตุผลที่ใช้ PostgreSQL: [docs/why-postgresql.md](docs/why-postgresql.md)
- อธิบายทีละ procedure: [docs/procedure-walkthrough.md](docs/procedure-walkthrough.md)

รันเร็วๆ (ต้องมี Docker และ client `psql`):

```bash
make test
```
