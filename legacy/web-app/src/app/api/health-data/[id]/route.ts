import {NextRequest, NextResponse} from "next/server";
import prisma, {Prisma} from "@/lib/prisma";
import {HealthData} from "@/app/api/health-data/route";

export interface HealthDataPatchRequest {
    data?: Prisma.InputJsonValue
}

export interface HealthDataGetResponse {
    healthData: HealthData
}

export async function GET(
    req: NextRequest,
    {params}: { params: Promise<{ id: string }> }
) {
    const {id} = await params
    const healthData = await prisma.healthData.findUniqueOrThrow({where: {id}})
    return NextResponse.json({healthData})
}

export async function PATCH(
    req: NextRequest,
    {params}: { params: Promise<{ id: string }> }
) {
    const {id} = await params
    const body: HealthDataPatchRequest = await req.json()

    try {
        const healthData = await prisma.healthData.update({
            where: {id},
            data: body
        })
        return NextResponse.json({healthData})
    } catch (error) {
        if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2025') {
            // Record not found
            return NextResponse.json({ error: 'Health data not found' }, { status: 404 });
        }
        throw error;
    }
}

export async function DELETE(
    req: NextRequest,
    {params}: { params: Promise<{ id: string }> }
) {
    const {id} = await params
    await prisma.healthData.delete({where: {id}})
    return NextResponse.json({})
}
