import 'package:flutter/material.dart';

class HeVerificationGuide extends StatelessWidget {
  const HeVerificationGuide({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Row(
            children: [
              Icon(Icons.verified_user, size: 24, color: cs.primary),
              const SizedBox(width: 10),
              Text(
                'OpenFHE Verification Guide',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Section 1: What is HE in EyeD?
          _Section(
            title: '1. What is HE in EyeD?',
            cs: cs,
            children: [
              _Paragraph(
                'EyeD uses OpenFHE with the BFV (Brakerski-Fan-Vercauteren) homomorphic '
                'encryption scheme to protect iris templates at rest and enable encrypted '
                'matching without ever decrypting the biometric data.',
                cs: cs,
              ),
              const SizedBox(height: 12),
              _InfoTable(
                cs: cs,
                rows: const [
                  ['Scheme', 'BFV (Brakerski-Fan-Vercauteren)'],
                  ['Plaintext modulus (t)', '65537'],
                  ['Ring dimension (N)', '8192'],
                  ['Security level', '128-bit (HEStd_128_classic)'],
                  ['Typical ciphertext count', '3 per iris code set'],
                  ['Encrypted template size', '~1.2 MB (vs ~96 KB plaintext)'],
                ],
              ),
            ],
          ),

          // Section 2: How to check HE is enabled
          _Section(
            title: '2. Checking HE Status',
            cs: cs,
            children: [
              _Paragraph(
                'HE is controlled by the EYED_HE_ENABLED environment variable. '
                'When enabled, all newly enrolled templates are stored as BFV ciphertexts.',
                cs: cs,
              ),
              const SizedBox(height: 12),
              _CodeBlock(
                cs: cs,
                code: '# In docker-compose.yml or environment:\n'
                    'EYED_HE_ENABLED=true\n'
                    'EYED_HE_KEY_DIR=/keys  # contains public.key, eval keys',
              ),
              const SizedBox(height: 12),
              _Paragraph(
                'Verify via the health endpoint:',
                cs: cs,
              ),
              const SizedBox(height: 8),
              _CodeBlock(
                cs: cs,
                code: 'curl http://localhost:9500/health/ready | python3 -m json.tool\n\n'
                    '# Look for:\n'
                    '#   "he_enabled": true\n'
                    '#   "he_key_loaded": true',
              ),
              const SizedBox(height: 12),
              _Paragraph(
                'In the DB Inspector "Schema" tab, HE templates show the "HEv1" badge '
                'and a larger blob size (~1.2 MB vs ~96 KB for NPZ).',
                cs: cs,
              ),
            ],
          ),

          // Section 3: Step-by-step verification
          _Section(
            title: '3. Step-by-Step Verification',
            cs: cs,
            children: [
              _Step(
                number: 1,
                title: 'Enroll a test identity with HE enabled',
                cs: cs,
                children: [
                  _CodeBlock(
                    cs: cs,
                    code: 'curl -X POST http://localhost:9500/enroll \\\n'
                        '  -H "Content-Type: application/json" \\\n'
                        '  -d \'{\n'
                        '    "identity_id": "he-test-001",\n'
                        '    "identity_name": "HE Test User",\n'
                        '    "jpeg_b64": "<base64-eye-image>",\n'
                        '    "eye_side": "left"\n'
                        '  }\'',
                  ),
                ],
              ),
              _Step(
                number: 2,
                title: 'Open DB Inspector and browse the templates table',
                cs: cs,
                children: [
                  _Paragraph(
                    'Navigate to DB Inspector > Browse tab > select "templates". '
                    'Find the row for your test identity. The iris_codes and mask_codes '
                    'columns should show HEv1 chips instead of NPZ.',
                    cs: cs,
                  ),
                ],
              ),
              _Step(
                number: 3,
                title: 'Click the template row to view details',
                cs: cs,
                children: [
                  _Paragraph(
                    'The row detail dialog shows the BYTEA metadata card for each '
                    'encrypted column:',
                    cs: cs,
                  ),
                  const SizedBox(height: 8),
                  _InfoTable(
                    cs: cs,
                    rows: const [
                      ['Format', 'HEv1 (BFV ciphertexts)'],
                      ['Ciphertexts', '3 (one per iris code scale)'],
                      ['Size', '~1.2 MB total'],
                      ['Hex prefix', 'Starts with 48 45 76 31 (HEv1)'],
                    ],
                  ),
                ],
              ),
              _Step(
                number: 4,
                title: 'Verify matching works with encrypted templates',
                cs: cs,
                children: [
                  _CodeBlock(
                    cs: cs,
                    code: 'curl -X POST http://localhost:9500/analyze \\\n'
                        '  -F "file=@same_eye_image.jpg" \\\n'
                        '  -F "eye_side=left"\n\n'
                        '# Response should include:\n'
                        '#   "match": true\n'
                        '#   "identity_id": "he-test-001"\n'
                        '#   "hamming_distance": 0.XX',
                  ),
                  const SizedBox(height: 8),
                  _Paragraph(
                    'Matching is performed using homomorphic operations on the encrypted '
                    'iris codes. The server never sees the decrypted template.',
                    cs: cs,
                  ),
                ],
              ),
            ],
          ),

          // Section 4: Compare HE vs Plaintext
          _Section(
            title: '4. HE vs Plaintext Comparison',
            cs: cs,
            children: [
              _Paragraph(
                'Enroll the same identity with HE disabled (EYED_HE_ENABLED=false) '
                'and compare the template storage:',
                cs: cs,
              ),
              const SizedBox(height: 12),
              _InfoTable(
                cs: cs,
                rows: const [
                  ['', 'Plaintext (NPZ)', 'Encrypted (HEv1)'],
                  ['Format', 'NumPy compressed', 'BFV ciphertexts'],
                  ['iris_codes size', '~96 KB', '~1.2 MB'],
                  ['mask_codes size', '~96 KB', '~1.2 MB'],
                  ['Hex prefix', 'PK\\x03\\x04', 'HEv1'],
                  ['Ciphertext count', 'N/A', '3'],
                  ['Matching speed', '~2ms', '~50ms'],
                  ['Security', 'Plaintext at rest', '128-bit HE'],
                ],
              ),
              const SizedBox(height: 12),
              _Paragraph(
                'Use the DB Inspector "Schema" tab stats bar to see the count of HE '
                'versus plaintext templates in the database.',
                cs: cs,
              ),
            ],
          ),

          // Section 5: Architecture
          _Section(
            title: '5. HE Architecture',
            cs: cs,
            children: [
              _CodeBlock(
                cs: cs,
                code: '┌─────────────────────────┐\n'
                    '│      iris-engine        │\n'
                    '│  ┌─────────────────┐    │\n'
                    '│  │  Public Key      │    │     ┌──────────────┐\n'
                    '│  │  (encrypt only)  │───────►│  PostgreSQL  │\n'
                    '│  └─────────────────┘    │     │  (HEv1 blobs)│\n'
                    '│  ┌─────────────────┐    │     └──────────────┘\n'
                    '│  │  Eval Keys       │    │\n'
                    '│  │  (HE matching)   │    │\n'
                    '│  └─────────────────┘    │\n'
                    '└─────────────────────────┘\n'
                    '\n'
                    '┌─────────────────────────┐\n'
                    '│    key-service (future)  │\n'
                    '│  ┌─────────────────┐    │\n'
                    '│  │  Secret Key      │    │\n'
                    '│  │  (decrypt only)  │    │\n'
                    '│  └─────────────────┘    │\n'
                    '└─────────────────────────┘',
              ),
              const SizedBox(height: 12),
              _Paragraph(
                'The iris-engine holds only the public key (for encryption) and '
                'evaluation keys (for homomorphic matching). The secret key '
                'is held by a separate key-service (planned) and is never '
                'exposed to the enrollment or matching pipeline.',
                cs: cs,
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable building blocks
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  final String title;
  final ColorScheme cs;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.cs,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _Paragraph extends StatelessWidget {
  final String text;
  final ColorScheme cs;

  const _Paragraph(this.text, {required this.cs});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 14, color: cs.onSurface, height: 1.5),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String code;
  final ColorScheme cs;

  const _CodeBlock({required this.code, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: SelectableText(
        code,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: cs.onSurface,
          height: 1.5,
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String title;
  final ColorScheme cs;
  final List<Widget> children;

  const _Step({
    required this.number,
    required this.title,
    required this.cs,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                ...children,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTable extends StatelessWidget {
  final ColorScheme cs;
  final List<List<String>> rows;

  const _InfoTable({required this.cs, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Table(
          border: TableBorder.symmetric(
            inside: BorderSide(color: cs.outlineVariant, width: 0.5),
          ),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: rows.asMap().entries.map((entry) {
            final isHeader = entry.key == 0;
            return TableRow(
              decoration: BoxDecoration(
                color: isHeader ? cs.surfaceContainer : null,
              ),
              children: entry.value.map((cell) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    cell,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
                      fontFamily: isHeader ? null : 'monospace',
                      color: cs.onSurface,
                    ),
                  ),
                );
              }).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }
}
