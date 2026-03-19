/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        wine: {
          50:  '#fdf2f4',
          100: '#fce7eb',
          500: '#9b1b30',
          600: '#7d1626',
          700: '#5f1020',
          900: '#2d0710',
        },
      },
    },
  },
  plugins: [],
}
