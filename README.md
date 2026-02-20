# 🎮 A* Pathfinding pada Grid Hexagonal (Diamond Isometric) — Godot

> Implementasi algoritma A* untuk pergerakan berbasis hex grid dalam game roguelike menggunakan Godot Engine.

**Nama:** Vincent Timothy Kurniawan  
**Kelas:** 12.2

---

## 📖 Deskripsi

Proyek ini menerapkan algoritma **A\* (A-Star)** pada sistem pergerakan **hexagonal diamond isometric** dalam video game bergenre roguelike. Sistem pathfinding ini memungkinkan karakter bergerak secara otomatis dan optimal di atas tilemap berbentuk segi enam.

---

## 🔷 Hexagonal Movement

**Hexagonal movement** adalah sistem pergerakan pada ruang/grid yang tersusun dari sel berbentuk segi enam (hexagon), di mana suatu objek dapat berpindah dari satu sel ke sel tetangga yang berbatasan langsung.

Berbeda dengan grid kotak yang memiliki 4 atau 8 arah gerak, pada grid hexagonal setiap sel hanya terhubung langsung ke **6 sel** di sekelilingnya:

| Arah | Vektor |
|------|--------|
| Ke kanan (East) | `(1, 0)` |
| Ke kanan-atas (Northeast) | `(1, -1)` |
| Ke kiri-atas (North) | `(0, -1)` |
| Ke kiri (West) | `(-1, 0)` |
| Ke kiri-bawah (Southwest) | `(-1, 1)` |
| Ke kanan-bawah (South) | `(0, 1)` |

---

## ⭐ Algoritma A*

**A\*** adalah algoritma pencarian jalur (*pathfinding*) yang digunakan untuk menemukan rute paling pendek atau paling efisien dari satu titik ke titik tujuan. Algoritma ini sangat populer dalam pengembangan game, robotika, navigasi peta, dan kecerdasan buatan.

### Rumus Utama

```
f(n) = g(n) + h(n)
```

| Variabel | Keterangan |
|----------|-----------|
| `g(n)` | Biaya/jarak dari titik awal ke posisi sekarang |
| `h(n)` | Perkiraan jarak dari posisi sekarang ke tujuan *(heuristic)* |
| `f(n)` | Total nilai yang digunakan untuk menentukan jalur terbaik |

### Cara Kerja

1. Tentukan titik awal *(start)* dan titik tujuan *(goal)*
2. Mulai dari titik awal, periksa semua tetangga di sekitarnya
3. Hitung nilai `g`, `h`, dan `f` untuk setiap tetangga
4. Pilih posisi dengan nilai `f` paling kecil
5. Ulangi proses hingga mencapai tujuan
6. Setelah tujuan ditemukan, jalur disusun kembali dari awal ke akhir

---

## ⚙️ Fitur Sistem

- ✅ Pathfinding A* pada grid hex diamond isometric
- ✅ Preview jalur sebelum bergerak
- ✅ Animasi squash & stretch saat berjalan
- ✅ Interaksi tile (ambil koin, tabrak musuh, pengurangan HP)
- ✅ Validasi tile dapat dilalui

---

## 🧩 Kode Utama

### Variabel yang Dapat Dikonfigurasi

```gdscript
@export var tileMap : TileMapLayer
@export var offSet = Vector2(0, -8)
@export var movement_speed := 0.1
@export var show_path_preview := true
@export var path_preview_color := Color(1, 1, 0, 0.8)
@export var allow_diagonal := true
```

### Representasi Grid Hexagonal

```gdscript
const HEX_DIRECTIONS_DIAMOND := [
    Vector2i(1, 0),   # East
    Vector2i(1, -1),  # Northeast
    Vector2i(0, -1),  # North
    Vector2i(-1, 0),  # West
    Vector2i(-1, 1),  # Southwest
    Vector2i(0, 1),   # South
]
```

### Pseudocode: `MOVE()`

```
FUNCTION MOVE():
    IF isMoving = TRUE → RETURN
    IF player NOT alive → RETURN

    targetPosition ← mouse global position
    IF targetPosition INVALID → RETURN

    isMoving ← TRUE
    movementArray ← GET_ROUTE_ASTAR(targetPosition)

    IF movementArray EMPTY:
        isMoving ← FALSE
        RETURN

    FOR EACH movement IN movementArray:
        targetTile ← playerTile + movement
        ANIMATE_MOVEMENT(player, targetWorldPos)
        CHECK_TILE_INTERACTIONS(targetTile)
        IF player NOT alive → BREAK

    isMoving ← FALSE
END FUNCTION
```

### Pseudocode: `GET_ROUTE_ASTAR()`

```
FUNCTION GET_ROUTE_ASTAR(targetPosition):
    start_tile ← tileMap.local_to_map(player.position)
    target_tile ← tileMap.local_to_map(targetPosition)

    open_set ← [start_tile]
    came_from ← {}
    g_score[start_tile] ← 0
    f_score[start_tile] ← HEX_DISTANCE(start_tile, target_tile)
    max_iterations ← 1000

    WHILE open_set NOT empty AND iterations < max_iterations:
        current ← node IN open_set WITH lowest f_score

        IF current = target_tile:
            RETURN RECONSTRUCT_PATH(came_from, current)

        FOR EACH direction IN HEX_DIRECTIONS:
            neighbor ← current + direction
            IF NOT WALKABLE(neighbor) → CONTINUE

            tentative_g ← g_score[current] + 1
            IF tentative_g < g_score[neighbor]:
                came_from[neighbor] ← current
                g_score[neighbor] ← tentative_g
                f_score[neighbor] ← tentative_g + HEX_DISTANCE(neighbor, target_tile)
                ADD neighbor TO open_set (if not already)

    RETURN empty array
END FUNCTION
```

---

## 📊 Perbandingan Algoritma Pathfinding

| Algoritma | Cara Kerja | Kelebihan | Kekurangan | Cocok Untuk |
|-----------|-----------|-----------|------------|-------------|
| **A\*** | Jarak asli + estimasi ke tujuan | Cepat, optimal, fokus ke target | Perlu heuristic yang bagus | Game, AI, hex grid |
| **Dijkstra** | Cek semua jalur biaya terkecil | Pasti menemukan jalur terpendek | Lambat karena eksplorasi luas | Map kecil, tanpa target jelas |
| **BFS** | Menyebar ke semua arah | Sederhana, mudah dibuat | Tidak efisien di map besar | Grid kecil, tanpa bobot |
| **DFS** | Telusuri satu jalur sampai mentok | Sangat ringan | Tidak menjamin jalur terpendek | Eksplorasi sederhana |
| **Greedy Best First** | Hanya estimasi ke target | Sangat cepat | Bisa salah pilih jalur | AI sederhana |
| **Theta\*** | Versi lanjutan A* lebih smooth | Jalur lebih natural | Lebih kompleks | Navigasi realistis |

---

## ✅ Kelebihan A*

1. **Menemukan jalur terpendek (optimal)** — selalu menemukan rute terbaik jika heuristic akurat
2. **Lebih cepat dari Dijkstra** — tidak mengecek semua kemungkinan jalur
3. **Efisien untuk game** — cocok untuk NPC mengejar player, sistem taktik berbasis tile
4. **Fleksibel** — bisa digunakan pada grid kotak, hex, maupun graph bebas
5. **Mendukung obstacle** — tile yang tidak bisa dilewati langsung diabaikan

## ❌ Kekurangan A*

1. **Bergantung pada heuristic** — jika `h(n)` buruk, jalur bisa tidak optimal
2. **Memakan memori lebih besar** — menyimpan `open_set`, `g_score`, `f_score`, `came_from`
3. **Bisa berat pada map sangat besar** — performa menurun dengan banyak obstacle
4. **Lebih kompleks** — implementasi lebih rumit dibanding BFS/Dijkstra
5. **Tetap mahal secara komputasi** — jika target sangat jauh, banyak node harus diperiksa

---

## 🛠️ Teknologi

- [Godot Engine](https://godotengine.org/)
- GDScript
- TileMapLayer (Hex Diamond Isometric)
