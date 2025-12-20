import { motion } from 'framer-motion'

const items = [
    {
        title: "Health Intelligence",
        desc: "Advanced metrics visualization that adapts to your body's rhythm.",
        img: "/assets/graphs.png",
        colSpan: "col-span-1 md:col-span-2",
        rowSpan: ""
    },
    {
        title: "Smart Scheduling",
        desc: "A calendar that respects your energy levels.",
        img: "/assets/eventdetails.png",
        colSpan: "col-span-1",
        rowSpan: "row-span-2"
    },
    {
        title: "Instant Capture",
        desc: "Never lose a fleeting thought.",
        img: "/assets/notepad.png",
        colSpan: "col-span-1",
        rowSpan: ""
    },
    {
        title: "Precision Tracking",
        desc: "Custom variables for your unique life.",
        img: "/assets/variables.png",
        colSpan: "col-span-1",
        rowSpan: ""
    }
]

export default function BentoGrid() {
    return (
        <section className="py-20 bg-black" id="tech-specs">
            <div className="max-w-[1080px] mx-auto px-6">
                <motion.div
                    initial={{ opacity: 0, y: 20 }}
                    whileInView={{ opacity: 1, y: 0 }}
                    viewport={{ once: true }}
                    className="text-center mb-16"
                >
                    <h2 className="text-4xl font-display font-bold mb-4">Everything in sync.</h2>
                    <p className="text-xl text-gray-400">Designed to be as powerful as it is personal.</p>
                </motion.div>

                <div className="grid grid-cols-1 md:grid-cols-3 gap-6 auto-rows-[400px]">
                    {items.map((item, i) => (
                        <motion.div
                            key={i}
                            initial={{ opacity: 0, y: 20 }}
                            whileInView={{ opacity: 1, y: 0 }}
                            viewport={{ once: true }}
                            transition={{ delay: i * 0.1 }}
                            className={`relative group overflow-hidden rounded-3xl border border-white/10 bg-surface-glass hover:border-white/20 transition-colors ${item.colSpan} ${item.rowSpan}`}
                        >
                            <div className="absolute inset-0 bg-gradient-to-b from-transparent to-black/80 z-10" />
                            <div className="relative z-20 p-8 h-full flex flex-col">
                                <div>
                                    <h3 className="text-2xl font-bold mb-2">{item.title}</h3>
                                    <p className="text-gray-400">{item.desc}</p>
                                </div>
                            </div>
                            <motion.img
                                src={item.img}
                                alt={item.title}
                                className="absolute bottom-0 left-0 w-full object-contain object-bottom translate-y-10 group-hover:translate-y-0 transition-transform duration-500 ease-out"
                            />
                        </motion.div>
                    ))}
                </div>
            </div>
        </section>
    )
}
